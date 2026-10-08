# Snowflake side of the Britive Snowflake and Snowflake Standalone
# applications: a role with MANAGE GRANTS, optionally ORGADMIN, and a service
# user holding that role with key-pair authentication.
# Matches docs.britive.com/docs/configuring-on-snowflake-application.

provider "snowflake" {
  organization_name      = var.snowflake_organization
  account_name           = var.snowflake_account
  user                   = var.snowflake_admin_user
  role                   = var.snowflake_admin_role
  authenticator          = "SNOWFLAKE_JWT"
  private_key            = file(pathexpand(var.snowflake_admin_private_key_file))
  private_key_passphrase = var.snowflake_admin_private_key_passphrase
}

locals {
  # Snowflake wants the key body only: no PEM header or trailer, one line.
  britive_public_key = replace(trimspace(file(pathexpand(var.britive_public_key_file))), "/-----[A-Z ]+-----|\\s/", "")
}

resource "snowflake_account_role" "britive" {
  name    = var.britive_role_name
  comment = "Used by Britive to manage grants"
}

resource "snowflake_grant_privileges_to_account_role" "manage_grants" {
  account_role_name = snowflake_account_role.britive.name
  privileges        = ["MANAGE GRANTS"]
  on_account        = true
}

# Snowflake organization application only: ORGADMIN is granted to the Britive
# role. Terraform must run as ORGADMIN for this grant.
resource "snowflake_grant_account_role" "orgadmin" {
  count = var.grant_orgadmin ? 1 : 0

  role_name        = "ORGADMIN"
  parent_role_name = snowflake_account_role.britive.name
}

resource "snowflake_service_user" "britive" {
  name           = var.britive_user_name
  comment        = "Britive integration; key-pair authentication only"
  default_role   = snowflake_account_role.britive.name
  rsa_public_key = local.britive_public_key
}

resource "snowflake_grant_account_role" "user" {
  role_name = snowflake_account_role.britive.name
  user_name = snowflake_service_user.britive.name
}
