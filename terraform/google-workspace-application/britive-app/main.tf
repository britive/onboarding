# The Britive "Google Workspace" application, built from what ../ (the
# service account and key) and ../../google-workspace (the admin user Britive
# acts as) created. Run it after both.
#
# Property names are the provider's for this application type (its acceptance
# tests); the key goes in the same sensitive property the GCP application
# uses. Console equivalent: docs.britive.com/docs/onboarding-gws.
#
# After the first apply, open the application in the Britive console, select
# Save and Test, then Scan.

data "terraform_remote_state" "gcp" {
  backend = "local"
  config  = { path = "${path.module}/../terraform.tfstate" }
}

locals {
  gcp = data.terraform_remote_state.gcp.outputs

  workspace_state = "${path.module}/../../google-workspace/terraform.tfstate"
  workspace       = fileexists(local.workspace_state) ? jsondecode(file(local.workspace_state)).outputs : {}
  gsuite_admin    = coalesce(var.gsuite_admin_email, try(local.workspace.gsuite_admin_email.value, null), "unset")

  google_domain  = coalesce(var.google_domain, local.gcp.workspace_domain)
  replace_domain = var.britive_users_domain != null && var.britive_users_domain != local.google_domain

  properties = merge(
    {
      displayName                     = var.application_name
      description                     = "Google Workspace ${local.google_domain}"
      appAccessMethod_static_loginUrl = var.login_url
      gSuiteAdmin                     = local.gsuite_admin
      provisionUserGw                 = var.create_user_for_super_admin
      scanRoles                       = var.scan_roles
      scanGroups                      = var.scan_groups
      enableSso                       = var.enable_sso
      replaceDomain                   = local.replace_domain
      maxSessionDurationForProfiles   = var.max_session_duration_seconds
    },
    # Google's SAML service-provider values for a Workspace domain; the console
    # pre-fills them with {domain} for you to replace.
    var.enable_sso ? {
      audience = "google.com/a/${local.google_domain}"
      acsUrl   = "https://www.google.com/a/${local.google_domain}/acs"
    } : {},
    local.replace_domain ? {
      primaryDomain   = var.britive_users_domain
      secondaryDomain = local.google_domain
    } : {},
  )
}

resource "britive_application" "workspace" {
  application_type = "Google Workspace"

  lifecycle {
    precondition {
      condition     = local.gsuite_admin != "unset"
      error_message = "The Workspace admin user is unknown: apply ../../google-workspace first, or set gsuite_admin_email."
    }
  }

  user_account_mappings {
    name        = "Email"
    description = "Map Britive users to Google Workspace by email"
  }

  dynamic "properties" {
    for_each = local.properties
    content {
      name  = properties.key
      value = tostring(properties.value)
    }
  }

  sensitive_properties {
    name  = "serviceAccountCredentials"
    value = file(local.gcp.service_account_key_file)
  }
}

output "application_id" {
  value = britive_application.workspace.id
}

output "next_step" {
  value = "Britive console -> System Administration -> Tenant Applications -> ${var.application_name} -> Save and Test, then Scan. Create profiles once the scan has finished."
}
