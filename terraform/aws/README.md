# Britive AWS Integration - Terraform

This directory contains Terraform configurations for deploying Britive integration resources on AWS. These Terraform modules are equivalent to the CloudFormation templates found in the `cloudformation/aws/` directory.

## Overview

Three deployment options are available, matching the CloudFormation examples:

### 1. [Organization StackSet](organization-stackset/)

**Use case**: Deploy across an entire AWS Organization

Creates resources in the master account and uses CloudFormation StackSets to deploy integration resources across all accounts in an organizational unit.

**Resources**:

- SAML provider and integration role in master account
- CloudFormation StackSet for organization-wide deployment
- Auto-deployment to new accounts

**Matches CloudFormation**: `cloudformation/aws/organization-stackset/`

---

### 2. [Full Lab Setup](full-lab-setup/)

**Use case**: Complete test/demo environment with infrastructure

Creates a comprehensive lab environment including Britive integration plus test infrastructure.

**Resources**:

- SAML provider and integration role
- VPC with public subnets
- Linux and Windows EC2 instances
- MySQL RDS instance
- KMS encryption and Secrets Manager
- Four test roles for JIT access demonstration

**Matches CloudFormation**: `cloudformation/aws/full-lab-setup/`

---

### 3. [Single Account Stack](single-account-stack/)

**Use case**: Simple single-account deployment

The minimal setup for Britive integration. Available in two variants:

- **Basic**: Just SAML provider and integration role
- **With Roles**: Adds four test roles for demonstration

**Matches CloudFormation**: `cloudformation/aws/single-account-stack/`

---

## Quick Start

1. Choose the deployment option that fits your needs
2. Navigate to the corresponding directory
3. Follow the README instructions in that directory

## Prerequisites

All configurations require:

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- SAML metadata document from your Britive tenant

Additional requirements vary by deployment option - see individual READMEs.

## Common Configuration

All deployments use similar variables:

```hcl
tenant_name                        = "your-tenant-name"  # Omit .britive-app.com
saml_metadata_document_xml_content = "<SAML XML content>"
deploy_aws_invalidation_feature    = true
```

## Comparison with CloudFormation

| Feature | CloudFormation | Terraform |
|---------|---------------|-----------|
| **Organization StackSet** | Uses nested stacks and StackSet | Uses StackSet resource directly |
| **Full Lab Setup** | Single template with all resources | Single `main.tf` with organized sections |
| **Single Account** | Two separate templates | Two variants in one directory |
| **Parameters** | JSON parameters file | `.tfvars` file |
| **Outputs** | CloudFormation outputs | Terraform outputs |
| **Policy Attachments** | Inline in role definition | Separate `aws_iam_role_policy_attachment` resources |

## File Organization

Each directory follows Terraform best practices:

- `main.tf` - All resources (with clear section organization)
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `terraform.tfvars.example` - Example configuration
- `README.md` - Detailed documentation

**Note**: Some configurations may have additional `.tf` files (like `stackset.tf` in organization-stackset) for logical separation of complex resources.

## Key Improvements Over CloudFormation

These Terraform configurations include several improvements:

1. **No Deprecation Warnings**: Uses `aws_iam_role_policy_attachment` instead of deprecated `managed_policy_arns`
2. **Simplified Structure**: Full lab setup consolidated into a single, well-organized `main.tf`
3. **Clear Organization**: Resources grouped by type with section headers
4. **Modern Best Practices**: Uses current Terraform patterns and conventions
5. **Better Modularity**: Easy to customize individual sections

See [CHANGES.md](CHANGES.md) for detailed information about recent updates.

## Getting Help

For issues or questions:

- Check the README in each subdirectory
- Review the equivalent CloudFormation template for comparison
- Consult Terraform AWS provider documentation
- Review [CONVERSION_SUMMARY.md](CONVERSION_SUMMARY.md) for CloudFormation→Terraform mapping

## Migration from CloudFormation

If you're migrating from CloudFormation:

1. The resources created are functionally identical
2. Variable names closely match CloudFormation parameter names
3. Outputs provide the same information
4. Each Terraform directory's README explains the mapping to CloudFormation
5. See [CONVERSION_SUMMARY.md](CONVERSION_SUMMARY.md) for detailed resource mapping
