output "account_id" {
  description = "Account ID to enter in the Britive application."
  value       = module.britive.account_id
}

output "saml_provider_arn" {
  description = "ARN of the Britive SAML provider."
  value       = module.britive.saml_provider_arn
}

output "saml_provider_name" {
  description = "Enter as 'Identity Provider Name' in the Britive application."
  value       = module.britive.saml_provider_name
}

output "integration_role_arn" {
  description = "ARN of the Britive integration role."
  value       = module.britive.integration_role_arn
}

output "integration_role_name" {
  description = "Enter as 'Integration Role Name' in the Britive application."
  value       = module.britive.integration_role_name
}

output "backend_connection_duration_hours" {
  description = "Enter as 'Duration of backend connection' in the Britive application."
  value       = module.britive.backend_connection_duration_hours
}

output "sample_role_arns" {
  description = "Sample JIT role ARNs (empty unless deploy_sample_roles = true)."
  value       = module.britive.sample_role_arns
}
