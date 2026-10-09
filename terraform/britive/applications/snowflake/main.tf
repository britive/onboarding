# The Britive side of a Snowflake onboarding, after ../../../snowflake created
# the role and the service user. Two application types:
#
#   standalone = false  "Snowflake" (organization): connection properties on
#                       the application; Britive discovers the accounts.
#   standalone = true   "Snowflake Standalone": the application is a shell and
#                       each account is a britive_entity_environment with its
#                       own connection properties.
#
# Property names are the provider's (its documentation and acceptance tests).
# Console equivalents: docs.britive.com/docs/onboarding-snowflake-org-application-in-britive
# and onboarding-snowflake-in-britive-application.

locals {
  login_url_for = { for k, a in var.accounts : k => replace(var.login_url, "{accountId}", a.account_identifier) }

  # Snowflake wants the key bodies; the console upload accepts the PEM files.
  private_key = file(pathexpand(var.private_key_file))
  public_key  = file(pathexpand(var.public_key_file))

  connection_properties = {
    username                   = var.username
    role                       = var.role
    loginNameForAccountMapping = var.use_login_name_for_account_mapping
    snowflakeSchemaScanFilter  = var.skip_schema_level_privileges
  }
}

# ------------------------------------------------ organization application
resource "britive_application" "organization" {
  count = var.standalone ? 0 : 1

  application_type = "Snowflake"

  user_account_mappings {
    name        = var.account_mapping_attribute
    description = "Map Britive users to Snowflake by ${var.account_mapping_attribute}"
  }

  properties {
    name  = "displayName"
    value = var.application_name
  }
  properties {
    name  = "description"
    value = var.description
  }
  properties {
    name  = "maxSessionDurationForProfiles"
    value = var.max_session_duration_for_profiles
  }

  properties {
    name  = "accountId"
    value = var.account_identifier
  }
  properties {
    name  = "appAccessMethod_static_loginUrl"
    value = replace(var.login_url, "{accountId}", coalesce(var.account_identifier, "unset"))
  }
  dynamic "properties" {
    for_each = local.connection_properties
    content {
      name  = properties.key
      value = properties.value
    }
  }
  properties {
    name  = "copyAppToEnvProps"
    value = var.copy_settings_to_all_accounts
  }

  sensitive_properties {
    name  = "privateKey"
    value = local.private_key
  }
  sensitive_properties {
    name  = "publicKey"
    value = local.public_key
  }
  sensitive_properties {
    name  = "privateKeyPassword"
    value = var.private_key_passphrase
  }

  lifecycle {
    precondition {
      condition     = var.account_identifier != null
      error_message = "account_identifier is required for the organization application (standalone = false)."
    }
  }
}

# -------------------------------------------------- standalone application
resource "britive_application" "standalone" {
  count = var.standalone ? 1 : 0

  application_type = "Snowflake Standalone"

  user_account_mappings {
    name        = var.account_mapping_attribute
    description = "Map Britive users to Snowflake by ${var.account_mapping_attribute}"
  }

  properties {
    name  = "displayName"
    value = var.application_name
  }
  properties {
    name  = "description"
    value = var.description
  }
  properties {
    name  = "maxSessionDurationForProfiles"
    value = var.max_session_duration_for_profiles
  }

  lifecycle {
    precondition {
      condition     = length(var.accounts) > 0
      error_message = "accounts must list at least one Snowflake account for the standalone application (standalone = true)."
    }
  }
}

# One environment per account, under the application's root environment group.
resource "britive_entity_environment" "account" {
  for_each = var.standalone ? var.accounts : {}

  application_id  = britive_application.standalone[0].id
  parent_group_id = britive_application.standalone[0].entity_root_environment_group_id

  properties {
    name  = "displayName"
    value = each.key
  }
  properties {
    name  = "description"
    value = each.value.description
  }
  properties {
    name  = "accountId"
    value = each.value.account_identifier
  }
  properties {
    name  = "appAccessMethod_static_loginUrl"
    value = local.login_url_for[each.key]
  }
  dynamic "properties" {
    for_each = local.connection_properties
    content {
      name  = properties.key
      value = properties.value
    }
  }

  sensitive_properties {
    name  = "privateKey"
    value = local.private_key
  }
  sensitive_properties {
    name  = "publicKey"
    value = local.public_key
  }
  sensitive_properties {
    name  = "privateKeyPassword"
    value = var.private_key_passphrase
  }
}
