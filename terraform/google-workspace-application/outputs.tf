output "project_id" {
  description = "Project holding the Britive service account."
  value       = local.project_id
}

output "service_account_email" {
  description = "The Britive service account."
  value       = google_service_account.britive.email
}

output "service_account_client_id" {
  description = "Client ID to authorise under Security -> Access and data control -> API controls -> Manage Domain Wide Delegation."
  value       = google_service_account.britive.unique_id
}

output "delegation_scopes" {
  description = "OAuth scopes to enter with the client ID, comma separated."
  value       = join(",", local.delegation_scopes)
}

output "service_account_key_file" {
  description = "Path of the service account key: upload its contents to the Britive application (britive-app/ does it) and pass it to ../google-workspace."
  value       = abspath(local_sensitive_file.key.filename)
}

output "workspace_domain" {
  value = var.workspace_domain
}
