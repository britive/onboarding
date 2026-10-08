output "management_account_id" {
  description = "Enter as 'Management Account ID' in the Britive AWS application."
  value       = module.britive_management_account.account_id
}

output "identity_provider_name" {
  description = "Enter as 'Identity Provider Name'. The same name exists in every member account."
  value       = module.britive_management_account.saml_provider_name
}

output "integration_role_name" {
  description = "Enter as 'Integration Role Name'. The same name exists in every member account."
  value       = module.britive_management_account.integration_role_name
}

output "backend_connection_duration_hours" {
  description = "Enter as 'Duration of backend connection'."
  value       = module.britive_management_account.backend_connection_duration_hours
}

output "account_access_application_arn" {
  description = "Enter as 'AWS Account Access Application ARN' in the Britive AWS Account Access application (empty unless deploy_account_access = true)."
  value       = var.account_access_application_arn
}

output "stack_set_name" {
  description = "StackSet deploying the member-account resources."
  value       = aws_cloudformation_stack_set.britive_resources.name
}
