# Britive AWS Organization StackSet - Terraform

This Terraform configuration deploys Britive integration resources across an AWS Organization using CloudFormation StackSets.

## Overview

This setup creates:
- A SAML provider for Britive authentication in the master account
- A Britive integration role with necessary permissions in the master account
- A CloudFormation StackSet that deploys the same resources across all accounts in the specified organizational unit
- Optional AWS Invalidation feature permissions

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- AWS Organizations enabled
- Service-managed StackSet permissions configured
- SAML metadata document from your Britive tenant

## Files

- `main.tf` - Main resources (SAML provider and integration role for master account)
- `stackset.tf` - CloudFormation StackSet configuration for organization-wide deployment
- `variables.tf` - Input variable definitions
- `outputs.tf` - Output values
- `terraform.tfvars.example` - Example variables file

## Usage

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values:
   - `root_ou_id` - Your AWS Organization root OU ID
   - `tenant_name` - Your Britive tenant name (without .britive-app.com)
   - `saml_metadata_document_xml_content` - SAML metadata XML from Britive
   - `s3_bucket_name` - S3 bucket containing the CloudFormation template
   - `s3_key_for_iam_resources_template` - S3 key for the template

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

## Resources Created

### Master Account
- `aws_iam_saml_provider.britive` - SAML identity provider
- `aws_iam_role.britive_integration` - Integration role with read-only access
- `aws_iam_role_policy.aws_invalidation` - Optional policy for AWS invalidation feature

### Organization-wide (via StackSet)
- SAML provider in each account
- Integration role in each account
- Optional invalidation policy in each account

## Outputs

- `master_account_id` - AWS Account ID of the master account
- `identity_provider_name` - Name of the SAML provider
- `integration_role_name` - Name of the integration role

## Notes

- All resources are global IAM resources, so only one region is required
- The StackSet uses SERVICE_MANAGED permission model for automatic deployment to new accounts
- Auto-deployment is enabled to automatically deploy to new accounts added to the OU
- The AWS Invalidation feature is enabled by default but can be disabled via the variable
