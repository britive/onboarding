output "account_id" {
  description = "Account the integration was created in. Enter as 'Management Account ID' (or account ID) when creating the AWS application in Britive."
  value       = local.account_id
}

output "saml_provider_arn" {
  description = "ARN of the Britive SAML identity provider."
  value       = aws_iam_saml_provider.britive.arn
}

output "saml_provider_name" {
  description = "Name of the SAML provider. Enter as 'Identity Provider Name' in the Britive application."
  value       = aws_iam_saml_provider.britive.name
}

output "integration_role_arn" {
  description = "ARN of the integration role."
  value       = aws_iam_role.britive_integration.arn
}

output "integration_role_name" {
  description = "Name of the integration role. Enter as 'Integration Role Name' in the Britive application (the name, not the ARN)."
  value       = aws_iam_role.britive_integration.name
}

output "backend_connection_duration_hours" {
  description = "Enter as 'Duration of backend connection' in the Britive application; it must equal the role's maximum session duration."
  value       = var.max_session_duration / 3600
}

output "sample_role_arns" {
  description = "ARNs of the sample JIT roles, keyed by short name. Empty unless deploy_sample_roles is true."
  value       = { for k, r in aws_iam_role.sample : k => r.arn }
}
