variable "organization_id" {
  type = string
}

variable "common_resource_name" {
  type    = string
  default = "BritiveIntegration"
}

variable "key_filename" {
  type    = string
  default = "key.json"
}

variable "workspace_customer_id" {
  type = string
}

variable "workspace_domain" {
  type = string
}

variable "workspace_impersonation_email" {
  type = string
}

provider "googleworkspace" {
  customer_id  = var.workspace_customer_id
  oauth_scopes = [
    "https://www.googleapis.com/auth/admin.directory.rolemanagement",
    "https://www.googleapis.com/auth/admin.directory.user",
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/admin.directory.group",
    "https://www.googleapis.com/auth/admin.directory.group.member"
  ]
  credentials = "../keys/key.json"
  impersonated_user_email = var.workspace_impersonation_email
}

data "googleworkspace_privileges" "privileges" {}

locals {
  integration_privileges = [
    for priv in data.googleworkspace_privileges.privileges.items : priv
    if contains([
      "ORGANIZATION_UNITS_RETRIEVE", "USERS_RETRIEVE", "GROUPS_RETRIEVE", "GROUPS_UPDATE"
    ], priv.privilege_name)
  ]
}

resource "googleworkspace_role" "BritiveIntegration" {
  name = var.common_resource_name

  dynamic "privileges" {
    for_each = local.integration_privileges
    content {
      service_id     = privileges.value["service_id"]
      privilege_name = privileges.value["privilege_name"]
    }
  }
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "googleworkspace_user" "BritiveIntegration" {
  primary_email = "${lower(var.common_resource_name)}@${var.workspace_domain}"
  password      = random_password.password.result

  name {
    family_name = var.common_resource_name
    given_name  = "TerraformGenerated"
  }
}


resource "googleworkspace_role_assignment" "BritiveIntegration" {
  role_id     = googleworkspace_role.BritiveIntegration.id
  assigned_to = googleworkspace_user.BritiveIntegration.id
}


output "gsuite_admin_email" {
  value = googleworkspace_user.BritiveIntegration.primary_email
}
