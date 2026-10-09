output "application_id" {
  description = "Application (app container) ID. Use it as app_container_id for profiles, or look the application up by name with data.britive_application."
  value       = britive_application.aws.id
}

output "application_name" {
  description = "Name to use in data.britive_application lookups."
  value       = var.application_name
}
