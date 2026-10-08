# The Google Cloud side of the Britive GCP integration:
#   - a project that holds the Britive service account (created, or an existing one)
#   - the APIs Britive calls
#   - the Britive Integration Role (organisation custom role) and the service account
#     that holds it, at organisation, folder or project scope
#   - how Britive authenticates as that account: wif.tf (keyless, recommended) or
#     key.tf (legacy service account key)

locals {
  wif = var.integration_type == "wif"

  # Permissions from Britive's prerequisites for the GCP application.
  base_permissions = [
    "iam.roles.get",
    "iam.roles.list",
    "iam.serviceAccountKeys.create",
    "iam.serviceAccountKeys.delete",
    "iam.serviceAccountKeys.get",
    "iam.serviceAccountKeys.list",
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.delete",
    "iam.serviceAccounts.disable",
    "iam.serviceAccounts.enable",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.list",
    "iam.serviceAccounts.setIamPolicy",
    "iam.serviceAccounts.undelete",
    "iam.serviceAccounts.update",
    "orgpolicy.policy.get",
    "resourcemanager.folders.get",
    "resourcemanager.folders.getIamPolicy",
    "resourcemanager.folders.list",
    "resourcemanager.folders.setIamPolicy",
    "resourcemanager.organizations.get",
    "resourcemanager.organizations.getIamPolicy",
    "resourcemanager.organizations.setIamPolicy",
    "resourcemanager.projects.get",
    "resourcemanager.projects.getIamPolicy",
    "resourcemanager.projects.list",
    "resourcemanager.projects.setIamPolicy",
  ]
  # The organization guide lists four; the projects-only guide adds
  # bigquery.datasets.get (read-only), included so both scopes work.
  bigquery_permissions = [
    "bigquery.datasets.get",
    "bigquery.datasets.update",
    "bigquery.tables.get",
    "bigquery.tables.getIamPolicy",
    "bigquery.tables.setIamPolicy",
  ]
  apigee_permissions = [
    "apigee.environments.get",
    "apigee.environments.getIamPolicy",
    "apigee.environments.setIamPolicy",
  ]
  ai_scan_permissions = [
    "aiplatform.locations.get",
    "aiplatform.locations.list",
    "aiplatform.reasoningEngines.get",
    "aiplatform.reasoningEngines.list",
  ]
  role_permissions = concat(
    local.base_permissions,
    var.enable_bigquery_constraints ? local.bigquery_permissions : [],
    var.enable_apigee_constraints ? local.apigee_permissions : [],
    var.enable_ai_identity_scan ? local.ai_scan_permissions : [],
  )

  # Cloud Resource Manager, IAM and Directory are what Britive's prerequisites list.
  # WIF also needs the token exchange (STS) and impersonation (IAM Credentials) APIs.
  apis = concat(
    ["cloudresourcemanager.googleapis.com", "iam.googleapis.com", "admin.googleapis.com"],
    local.wif ? ["iamcredentials.googleapis.com", "sts.googleapis.com"] : [],
  )

  project_id     = var.create_project ? google_project.britive[0].project_id : data.google_project.existing[0].project_id
  project_number = var.create_project ? google_project.britive[0].number : data.google_project.existing[0].number
}

# ------------------------------------------------------------------------ project
resource "google_project" "britive" {
  count = var.create_project ? 1 : 0

  name                = var.project_name
  project_id          = var.project_id
  org_id              = var.folder_id == null ? var.organization_id : null
  folder_id           = var.folder_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = var.allow_project_deletion ? "DELETE" : "PREVENT"
}

data "google_project" "existing" {
  count      = var.create_project ? 0 : 1
  project_id = var.project_id
}

resource "google_project_service" "apis" {
  for_each = toset(local.apis)

  project            = local.project_id
  service            = each.value
  disable_on_destroy = false
}

# Newly enabled APIs take a minute to answer everywhere; without this the service
# account or the pool can fail with "API not enabled" on the first apply.
resource "time_sleep" "apis" {
  create_duration = "60s"
  depends_on      = [google_project_service.apis]
}

# ------------------------------------------------------------ role and service account
resource "google_organization_iam_custom_role" "britive" {
  org_id      = var.organization_id
  role_id     = var.role_id
  title       = "Britive Integration Role"
  description = "Permissions Britive needs to read IAM and grant roles just in time."
  stage       = "GA"
  permissions = local.role_permissions
}

resource "google_service_account" "britive" {
  project      = local.project_id
  account_id   = var.service_account_id
  display_name = "Britive integration"
  description  = local.wif ? "Impersonated by the Britive tenant through workload identity federation. No key." : "Used by the Britive GCP application with a service account key."
  depends_on   = [time_sleep.apis]
}

# The role is added for this one member; other members of the role are untouched.
resource "google_organization_iam_member" "britive" {
  count  = var.access_scope == "organization" ? 1 : 0
  org_id = var.organization_id
  role   = google_organization_iam_custom_role.britive.id
  member = "serviceAccount:${google_service_account.britive.email}"
}

# A missing scope_id fails the plan here (a precondition stops apply; a check
# block would only warn and then create the binding on "folders/none").
resource "google_folder_iam_member" "britive" {
  count  = var.access_scope == "folder" ? 1 : 0
  folder = "folders/${trimprefix(coalesce(var.scope_id, "none"), "folders/")}"
  role   = google_organization_iam_custom_role.britive.id
  member = "serviceAccount:${google_service_account.britive.email}"

  lifecycle {
    precondition {
      condition     = var.scope_id != null
      error_message = "scope_id (the folder number) is required when access_scope is \"folder\"."
    }
  }
}

resource "google_project_iam_member" "britive" {
  count   = var.access_scope == "project" ? 1 : 0
  project = coalesce(var.scope_id, "none")
  role    = google_organization_iam_custom_role.britive.id
  member  = "serviceAccount:${google_service_account.britive.email}"

  lifecycle {
    precondition {
      condition     = var.scope_id != null
      error_message = "scope_id (the project ID) is required when access_scope is \"project\"."
    }
  }
}
