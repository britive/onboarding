# Google Workspace side of the legacy (key-based) Britive GCP application only. The
# GCP WIF application does not use it.
#
# Creates a Workspace admin role limited to reading organisational units, users and
# groups and updating groups, and a dedicated Workspace user holding it. Britive's
# GCP application acts as that user ("G Suite admin") through domain-wide delegation
# granted to the service account from ../google-cloud.
#
# The user consumes a Workspace licence. Its password is random and only in state:
# Britive never signs in as it, it is impersonated.

provider "googleworkspace" {
  customer_id             = var.workspace_customer_id
  credentials             = var.service_account_key_file
  impersonated_user_email = var.workspace_impersonation_email
  oauth_scopes = [
    "https://www.googleapis.com/auth/admin.directory.rolemanagement",
    "https://www.googleapis.com/auth/admin.directory.user",
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/admin.directory.group",
    "https://www.googleapis.com/auth/admin.directory.group.member",
  ]
}

data "googleworkspace_privileges" "all" {}

locals {
  integration_privileges = [
    for p in data.googleworkspace_privileges.all.items : p
    if contains(["ORGANIZATION_UNITS_RETRIEVE", "USERS_RETRIEVE", "GROUPS_RETRIEVE", "GROUPS_UPDATE"], p.privilege_name)
  ]
}

resource "googleworkspace_role" "britive" {
  name = var.admin_role_name

  dynamic "privileges" {
    for_each = local.integration_privileges
    content {
      service_id     = privileges.value["service_id"]
      privilege_name = privileges.value["privilege_name"]
    }
  }
}

resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "googleworkspace_user" "britive" {
  primary_email = "${var.admin_user_name}@${var.workspace_domain}"
  password      = random_password.admin.result

  name {
    family_name = "Integration"
    given_name  = "Britive"
  }
}

resource "googleworkspace_role_assignment" "britive" {
  role_id     = googleworkspace_role.britive.id
  assigned_to = googleworkspace_user.britive.id
}
