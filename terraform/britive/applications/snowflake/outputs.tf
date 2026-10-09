output "application_id" {
  description = "Application (app container) ID, whichever type was created."
  value       = var.standalone ? britive_application.standalone[0].id : britive_application.organization[0].id
}

output "application_name" {
  description = "Name to use in data.britive_application lookups."
  value       = var.application_name
}

output "environment_ids" {
  description = "Standalone application: entity ID of each account's environment, keyed as in `accounts`."
  value       = { for k, e in britive_entity_environment.account : k => e.entity_id }
}
