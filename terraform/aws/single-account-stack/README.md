# Britive Single Account Stack - Terraform

This Terraform configuration deploys Britive integration resources to a single AWS account.

## Overview

This directory provides **two variants** matching the CloudFormation templates:

### 1. Basic Integration (default - `main.tf`)
Matches `britive_integration_resources.yaml`
- A SAML provider for Britive authentication
- A Britive integration role with necessary permissions (3600s max session)
- Optional AWS Invalidation feature permissions

### 2. Integration with Test Roles (`main-with-roles.tf.example`)
Matches `britive_integration_with_roles.yaml`
- Everything from the basic integration
- Extended max session duration (10800s)
- Four test roles for JIT access demonstration:
  - Readonly-admin-role
  - Poweruser-role
  - EC2-Fullaccess-role
  - S3-Fullaccess-role

This is the simplest deployment option, suitable for:
- Single AWS accounts
- Testing and evaluation
- Small deployments

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- SAML metadata document from your Britive tenant

## Files

- `main.tf` - Basic integration resources (SAML provider and integration role)
- `main-with-roles.tf.example` - Alternative main with test roles included
- `outputs.tf` - Output values for basic integration
- `outputs-with-roles.tf.example` - Alternative outputs for integration with test roles
- `variables.tf` - Input variable definitions
- `terraform.tfvars.example` - Example variables file

## Usage

### Option A: Basic Integration (default)

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values:
   - `tenant_name` - Your Britive tenant name (without .britive-app.com)
   - `saml_metadata_document_xml_content` - SAML metadata XML from Britive
   - `deploy_aws_invalidation_feature` - Enable/disable invalidation feature (default: true)

3. Initialize and apply:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

### Option B: Integration with Test Roles

1. Replace the main configuration with the test roles version:
   ```bash
   mv main.tf main-basic.tf.bak
   mv main-with-roles.tf.example main.tf
   mv outputs.tf outputs-basic.tf.bak
   mv outputs-with-roles.tf.example outputs.tf
   ```

2. Follow steps 1-3 from Option A above

## Resources Created

- `aws_iam_saml_provider.britive` - SAML identity provider for Britive
- `aws_iam_role.britive_integration` - Integration role with read-only access to IAM and Organizations
- `aws_iam_role_policy.aws_invalidation` - Optional inline policy for AWS invalidation feature

## Outputs

- `saml_provider_arn` - ARN of the SAML provider
- `saml_provider_name` - Name of the SAML provider
- `integration_role_arn` - ARN of the integration role
- `integration_role_name` - Name of the integration role

## Permissions

The integration role includes:
- `IAMReadOnlyAccess` - Read-only access to IAM resources
- `AWSOrganizationsReadOnlyAccess` - Read-only access to AWS Organizations

If AWS Invalidation is enabled, additional permissions are added:
- Policy management operations under `arn:aws:iam::*:policy/britive/managed/*`

## Integration with Britive

After deployment:
1. Note the SAML provider ARN and integration role name from the outputs
2. Configure these values in your Britive tenant
3. Test the integration by attempting to access AWS through Britive

## Cleanup

To destroy all resources:
```bash
terraform destroy
```
