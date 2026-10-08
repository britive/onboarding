# Britive application fields
output "account_id" {
  description = "Enter as the account ID in the Britive application."
  value       = module.britive.account_id
}

output "saml_provider_name" {
  description = "Enter as 'Identity Provider Name'."
  value       = module.britive.saml_provider_name
}

output "integration_role_name" {
  description = "Enter as 'Integration Role Name'."
  value       = module.britive.integration_role_name
}

output "backend_connection_duration_hours" {
  description = "Enter as 'Duration of backend connection'."
  value       = module.britive.backend_connection_duration_hours
}

output "sample_role_arns" {
  description = "The four sample JIT roles to attach to Britive profiles."
  value       = module.britive.sample_role_arns
}

# Lab infrastructure
output "vpc_id" {
  value = aws_vpc.britive.id
}

output "linux_instance_public_ip" {
  description = "ssh -i lab-key.pem ec2-user@<ip>"
  value       = aws_instance.linux.public_ip
}

output "windows_instance_id" {
  description = "Decrypt the Administrator password with: aws ec2 get-password-data --instance-id <id> --priv-launch-key lab-key.pem"
  value       = aws_instance.windows.id
}

output "windows_instance_public_ip" {
  value = aws_instance.windows.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.mysql.endpoint
}

output "rds_secret_arn" {
  description = "Secrets Manager secret with the MySQL administrator credentials."
  value       = aws_secretsmanager_secret.rds_password.arn
}

output "generated_private_key_pem" {
  description = "Private key of the generated key pair (empty when ssh_public_key was supplied). Save with: terraform output -raw generated_private_key_pem > lab-key.pem && chmod 600 lab-key.pem"
  value       = var.ssh_public_key == "" ? tls_private_key.generated[0].private_key_openssh : ""
  sensitive   = true
}
