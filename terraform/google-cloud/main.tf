variable "organization_id" {
  type = string
}

variable "common_resource_name" {
  type    = string
  default = "BritiveIntegration"
}

variable "workspace_customer_id" {
  type = string
}

variable "workspace_domain" {
  type = string
}

provider "google" {

}

resource "google_project" "BritiveIntegration" {
  name                = var.common_resource_name
  project_id          = lower(var.common_resource_name)
  org_id              = var.organization_id
}

resource "google_project_service" "cloudresourcemanager" {
  project = google_project.BritiveIntegration.project_id
  service = "cloudresourcemanager.googleapis.com"
}

resource "google_project_service" "iam" {
  project = google_project.BritiveIntegration.project_id
  service = "iam.googleapis.com"
}

resource "google_project_service" "admin" {
  project = google_project.BritiveIntegration.project_id
  service = "admin.googleapis.com"
}

resource "google_organization_iam_custom_role" "BritiveIntegration" {
  depends_on = [
    google_project_service.admin,
    google_project_service.cloudresourcemanager,
    google_project_service.iam
  ]
  role_id     = var.common_resource_name
  org_id      = var.organization_id
  title       = var.common_resource_name
  description = "required permissions for Britive to interact with GCP"
  stage       = "GA"
  permissions = [
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
    "resourcemanager.projects.setIamPolicy"
  ]
}

resource "google_service_account" "BritiveIntegration" {
  depends_on = [
    google_project_service.admin,
    google_project_service.cloudresourcemanager,
    google_project_service.iam
  ]
  account_id   = replace(lower(var.common_resource_name), " ", "")
  display_name = var.common_resource_name
  project = google_project.BritiveIntegration.project_id
}

resource "google_service_account_key" "BritiveIntegrationKey" {
  service_account_id = google_service_account.BritiveIntegration.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "local_sensitive_file" "key" {
  content_base64 = google_service_account_key.BritiveIntegrationKey.private_key
  filename       = "../keys/key.json"
}

resource "google_organization_iam_binding" "organization" {
  org_id = var.organization_id
  role   = google_organization_iam_custom_role.BritiveIntegration.id

  members = [
    "serviceAccount:${google_service_account.BritiveIntegration.email}"
  ]
}

output "organizations_unique_identifier" {
  value = var.organization_id
}

output "project_id_for_creating_service_accounts" {
  value = google_project.BritiveIntegration.project_id
}

output "customer_id_in_google_workspace_account_settings" {
  value = var.workspace_customer_id
}


