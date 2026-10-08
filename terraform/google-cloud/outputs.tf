# What the Britive application asks for. britive-app/ reads these from this root's
# state; for the console, copy them from `terraform output britive_application_values`.

output "integration_type" {
  value = var.integration_type
}

output "access_scope" {
  value = var.access_scope == "organization" ? "organization ${var.organization_id}" : "${var.access_scope} ${var.scope_id}"
}

output "britive_application_values" {
  description = "Field values for the Britive GCP WIF application (wif) or GCP application (key)."
  value = merge(
    {
      organization_id                          = var.organization_id
      project_id_for_creating_service_accounts = local.project_id
      service_account_email                    = google_service_account.britive.email
    },
    local.wif ? {
      britive_issuer_url                           = local.issuer_url
      workload_identity_pool_id                    = google_iam_workload_identity_pool.britive[0].workload_identity_pool_id
      workload_identity_provider_id                = google_iam_workload_identity_pool_provider.britive[0].workload_identity_pool_provider_id
      project_number_for_connected_service_account = local.project_number
      } : {
      service_account_key_file = abspath(local_sensitive_file.key[0].filename)
    },
  )
}

output "service_account_client_id" {
  description = "Key mode: the client ID to authorise for Google Workspace domain-wide delegation."
  value       = google_service_account.britive.unique_id
}
