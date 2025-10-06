output "saml_provider_arn" {
  description = "The ARN of the Britive SAML provider"
  value       = aws_iam_saml_provider.britive.arn
}

output "integration_role_arn" {
  description = "The ARN of the Britive integration role"
  value       = aws_iam_role.britive_integration.arn
}

output "integration_role_name" {
  description = "The name of the Britive integration role"
  value       = aws_iam_role.britive_integration.name
}

output "saml_provider_name" {
  description = "The name of the Britive SAML provider"
  value       = aws_iam_saml_provider.britive.name
}
