terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.76.0"
    }
  }
}

provider "snowflake" {
    organization_name = var.snowflake_organization  # required if not using profile. Can also be set via SNOWFLAKE_ORGANIZATION_NAME env var
    account_name = var.snowflake_account
    user     = var.snowflake_user
    password = var.snowflake_password
    role     = var.snowflake_admin_role
}

# Create a Custom Role for Britive
resource "snowflake_role" "britive_role" {
  name = var.britive_role_name
}

# Grant Required Privileges to the Custom Role
resource "snowflake_grant_privileges_to_account_role" "britive_role_grants" {
  account_role_name = snowflake_role.britive_role.name
  privileges        = var.britive_role_privileges
}

# Assign ORGADMIN Role to BRITIVEROLE
resource "snowflake_role_grants" "britive_orgadmin" {
  role_name = snowflake_role.britive_role.name
  roles     = [var.orgadmin_role]
}

# Create a User for Britive
resource "snowflake_user" "britive_user" {
  name          = var.britive_user_name
  default_role  = snowflake_role.britive_role.name
  rsa_public_key = file(var.britive_public_key_path)
}

# Assign the Custom Role to the User
resource "snowflake_role_grants" "britive_user_role" {
  role_name = snowflake_role.britive_role.name
  users     = [snowflake_user.britive_user.name]
}

# Output Public Key
output "britive_public_key" {
  value     = file(var.britive_public_key_path)
  sensitive = true
}
