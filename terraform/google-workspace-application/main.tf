# The Google Cloud side of the Britive "Google Workspace" application: a
# project with the Admin SDK API enabled, the service account Britive signs in
# with, and its key. Google Workspace itself then needs domain-wide delegation
# for that service account (a console step this root prints) and the GCDS admin
# role and user from ../google-workspace, which Britive impersonates.
#
# Matches docs.britive.com/docs/pre (Google Workspace prerequisites),
# enabling-cloud-apis-gw, domain-wide-delegation-gw, cis-custom-role-gcds and
# cis-custom-user.

locals {
  project_id = var.create_project ? google_project.britive[0].project_id : data.google_project.existing[0].project_id

  # Domain-wide delegation scopes from Britive's Google Workspace guide. The
  # rolemanagement scope is needed only when the super admin role is granted
  # through profiles; it is also what lets ../google-workspace create the admin
  # role through this service account.
  delegation_scopes = [
    "https://www.googleapis.com/auth/admin.directory.user",
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/admin.directory.group",
    "https://www.googleapis.com/auth/admin.directory.group.member",
    "https://www.googleapis.com/auth/admin.directory.rolemanagement",
    "https://www.googleapis.com/auth/admin.directory.customer.readonly",
    "https://www.googleapis.com/auth/admin.directory.domain.readonly",
  ]
}

# ------------------------------------------------------------------ project
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

# Admin SDK (Directory API) is what Britive calls; IAM for the service account.
resource "google_project_service" "apis" {
  for_each = toset(["admin.googleapis.com", "iam.googleapis.com", "cloudresourcemanager.googleapis.com"])

  project            = local.project_id
  service            = each.value
  disable_on_destroy = false
}

# Newly enabled APIs take a minute to answer everywhere; without this the
# service account can fail with "API not enabled" on the first apply.
resource "time_sleep" "apis" {
  create_duration = "60s"
  depends_on      = [google_project_service.apis]
}

# ---------------------------------------------------------- service account
resource "google_service_account" "britive" {
  project      = local.project_id
  account_id   = var.service_account_id
  display_name = "Britive Google Workspace"
  description  = "Used by the Britive Google Workspace application through domain-wide delegation"
  depends_on   = [time_sleep.apis]
}

# The key is uploaded to the Britive application and used by ../google-workspace.
# It is written to keys/key.json (mode 0600, git-ignored) and also held in
# this root's state: protect terraform.tfstate as you would the key.
resource "google_service_account_key" "britive" {
  service_account_id = google_service_account.britive.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "local_sensitive_file" "key" {
  content_base64       = google_service_account_key.britive.private_key
  filename             = "${path.module}/keys/key.json"
  file_permission      = "0600"
  directory_permission = "0700"
}
