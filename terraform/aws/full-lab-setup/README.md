# Britive Full Lab Setup - Terraform

This Terraform configuration creates a complete Britive integration lab environment on AWS.

## Overview

This setup creates a comprehensive test environment including:

### IAM Resources
- SAML provider for Britive authentication
- Britive integration role with read-only access to IAM and Organizations
- Optional AWS Invalidation feature permissions
- Four test roles (ReadOnly, PowerUser, EC2 Admin, S3 Admin) for JIT access testing

### Network Infrastructure
- VPC with DNS support (10.0.0.0/16)
- Two public subnets in different AZs
- Internet Gateway
- Route tables and associations
- Security group allowing SSH, RDP, and MySQL access

### Compute Resources
- Linux EC2 instance (Amazon Linux 2, t2.micro)
- Windows EC2 instance (Windows Server 2019, t3.small)
- EC2 key pair for SSH/RDP access

### Database Resources
- MySQL RDS instance (db.t3.micro)
- RDS subnet group
- Secrets Manager secret for database credentials
- KMS key for secret encryption

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- SAML metadata document from your Britive tenant
- SSH key pair (will be created if not provided)

## Files

- `main.tf` - All resources (IAM, VPC, EC2, RDS, KMS, Secrets, Test Roles)
- `variables.tf` - Input variable definitions
- `outputs.tf` - Output values
- `terraform.tfvars.example` - Example variables file
- `README.md` - This file

## Usage

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values:
   - `tenant_name` - Your Britive tenant name (without .britive-app.com)
   - `saml_metadata_document_xml_content` - SAML metadata XML from Britive
   - `ssh_public_key` - Your SSH public key (optional, for EC2 access)
   - `deploy_aws_invalidation_feature` - Enable/disable invalidation feature (default: true)

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Review the plan:
   ```bash
   terraform plan
   ```

5. Apply the configuration:
   ```bash
   terraform apply
   ```

## Outputs

After successful deployment, Terraform will output:
- VPC ID
- Linux and Windows instance IDs and public IPs
- RDS endpoint and credentials secret ARN
- Britive SAML provider and integration role ARNs
- Test role ARNs

## Testing JIT Access

The following test roles are created for demonstrating Britive JIT capabilities:
- `Readonly-admin-role` - Read-only access to AWS resources
- `Poweruser-role` - Power user access (all services except IAM)
- `EC2-Fullaccess-role` - Full access to EC2
- `S3-Fullaccess-role` - Full access to S3

## Security Notes

- The security group allows access from 0.0.0.0/0 for testing purposes
- In production, restrict access to specific IP ranges
- RDS is publicly accessible for testing - disable in production
- SSH keys should be managed securely
- Consider enabling MFA for sensitive operations

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

**Note**: Ensure you want to delete all resources before confirming the destroy operation.
