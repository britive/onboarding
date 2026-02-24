output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.britive.id
}

output "linux_instance_id" {
  description = "The ID of the Linux EC2 instance"
  value       = aws_instance.linux.id
}

output "linux_instance_public_ip" {
  description = "The public IP of the Linux EC2 instance"
  value       = aws_instance.linux.public_ip
}

output "windows_instance_id" {
  description = "The ID of the Windows EC2 instance"
  value       = aws_instance.windows.id
}

output "windows_instance_public_ip" {
  description = "The public IP of the Windows EC2 instance"
  value       = aws_instance.windows.public_ip
}

output "rds_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.mysql.endpoint
}

output "rds_secret_arn" {
  description = "The ARN of the RDS password secret"
  value       = aws_secretsmanager_secret.rds_password.arn
}

output "britive_saml_provider_arn" {
  description = "The ARN of the Britive SAML provider"
  value       = aws_iam_saml_provider.britive.arn
}

output "britive_integration_role_arn" {
  description = "The ARN of the Britive integration role"
  value       = aws_iam_role.britive_integration.arn
}

output "test_roles" {
  description = "ARNs of test roles created for Britive integration"
  value = {
    readonly_role  = aws_iam_role.readonly.arn
    poweruser_role = aws_iam_role.poweruser.arn
    ec2_admin_role = aws_iam_role.ec2_admin.arn
    s3_admin_role  = aws_iam_role.s3_admin.arn
  }
}
