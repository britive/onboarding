# The Britive application for the Google Cloud integration, built from what
# ../ (the google-cloud root) created. Run it after that root:
#   integration_type = "wif" -> application type "GCP WIF" (no key)
#   integration_type = "key" -> application type "GCP" (service account key, plus
#                               ../../google-workspace for the G Suite admin)
# After the first apply, open the application in the Britive console, select Save and
# Test, then Scan: profiles can only be associated with what the scan discovers.

data "terraform_remote_state" "gcp" {
  backend = "local"
  config  = { path = "${path.module}/../terraform.tfstate" }
}

locals {
  gcp    = data.terraform_remote_state.gcp.outputs
  values = local.gcp.britive_application_values
  wif    = local.gcp.integration_type == "wif"

  workspace_state = "${path.module}/../../google-workspace/terraform.tfstate"
  workspace       = !local.wif && fileexists(local.workspace_state) ? jsondecode(file(local.workspace_state)).outputs : {}
  gsuite_admin    = coalesce(var.gsuite_admin_email, try(local.workspace.gsuite_admin_email.value, null), "unset")
  customer_id     = coalesce(var.workspace_customer_id, try(local.workspace.workspace_customer_id.value, null), "unset")

  replace_domain = var.britive_users_domain != null && var.google_domain != null && var.britive_users_domain != var.google_domain

  common = merge(
    {
      displayName                     = var.application_name
      description                     = "Google Cloud organisation ${local.values.organization_id}"
      consoleAccess                   = true
      programmaticAccess              = var.programmatic_access
      appAccessMethod_static_loginUrl = "https://console.cloud.google.com"
      orgId                           = local.values.organization_id
      projectIdForServiceAccount      = local.values.project_id_for_creating_service_accounts
      enableSso                       = false
      maxSessionDurationForProfiles   = var.max_session_duration_seconds
      replaceDomain                   = local.replace_domain
    },
    local.replace_domain ? {
      primaryDomain   = var.britive_users_domain
      secondaryDomain = var.google_domain
    } : {},
  )

  properties = local.wif ? merge(local.common, {
    displayProgrammaticKeys = var.programmatic_access
    britiveIssuerUrl        = local.values.britive_issuer_url
    wifPool                 = local.values.workload_identity_pool_id
    wifProvider             = local.values.workload_identity_provider_id
    wifSA                   = local.values.service_account_email
    projectNumberForWifSA   = local.values.project_number_for_connected_service_account
    }) : merge(local.common, {
    gSuiteAdmin = local.gsuite_admin
    customerId  = local.customer_id
  })
}

check "workspace_values_for_key_mode" {
  assert {
    condition     = local.wif || (local.gsuite_admin != "unset" && local.customer_id != "unset")
    error_message = "Key mode needs the G Suite admin and customer ID: apply ../../google-workspace first, or set gsuite_admin_email and workspace_customer_id."
  }
}

resource "britive_application" "gcp" {
  application_type = local.wif ? "GCP WIF" : "GCP"

  dynamic "properties" {
    for_each = local.properties
    content {
      name  = properties.key
      value = tostring(properties.value)
    }
  }

  # Key mode: the service account key written by ../ (keys/key.json).
  dynamic "sensitive_properties" {
    for_each = local.wif ? {} : { serviceAccountCredentials = local.values.service_account_key_file }
    content {
      name  = sensitive_properties.key
      value = file(sensitive_properties.value)
    }
  }
}

output "application_id" {
  value = britive_application.gcp.id
}

output "next_step" {
  value = "Britive console -> Applications -> ${var.application_name} -> Save and Test, then Scan. Create profiles once the scan has finished."
}
