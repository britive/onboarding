output "master_account_id" {
  description = "The AWS Account ID where the master stack is deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "identity_provider_name" {
  description = "The name of the Britive SAML identity provider"
  value       = "britive-${var.tenant_name}"
}

output "integration_role_name" {
  description = "The name of the Britive integration role"
  value       = "britive-${var.tenant_name}-integration-role"
}

data "aws_caller_identity" "current" {}
