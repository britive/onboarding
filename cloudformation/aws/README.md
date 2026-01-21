# Britive AWS Integration - CloudFormation Templates

This directory contains CloudFormation templates for deploying Britive integration resources to AWS accounts. These templates enable Britive to manage Just-In-Time (JIT) access to your AWS environment through SAML federation.

## What is Britive?

Britive is a Privileged Access Management (PAM) platform that provides Just-In-Time (JIT) access to cloud environments. The AWS integration allows users to:

- Request temporary, time-limited access to AWS roles
- Authenticate via SAML federation (no long-lived credentials)
- Centrally manage and audit access across multiple AWS accounts

## Quick Start

| Use Case | Template Directory | Complexity |
|----------|-------------------|------------|
| Single account or POC | [single-account-stack/](single-account-stack/) | Low |
| Multi-account via StackSets | [stackset-templates/](stackset-templates/) | Medium |
| Entire organization (including management account) | [organization-stackset/](organization-stackset/) | High |
| Demo/lab environment with sample resources | [full-lab-setup/](full-lab-setup/) | Medium |

## Directory Structure

```
aws/
├── README.md                    # This file - overview and navigation
├── single-account-stack/        # Single account deployment templates
│   ├── britive_integration_resources.yaml
│   ├── britive_integration_with_roles.yaml
│   ├── parameters.json
│   └── README.md
├── stackset-templates/          # Multi-account StackSet deployment
│   ├── britive_integration_resources_stackset.yaml
│   ├── britive_integration_with_roles_stackset.yaml
│   ├── generate-parameters.sh
│   └── README.md
├── organization-stackset/       # Organization-wide deployment with nested stacks
│   ├── deploy_britive_integration_resources.yaml
│   ├── britive_integration_resources.yaml
│   ├── parameters.json
│   └── README.md
└── full-lab-setup/              # Complete demo environment
    ├── britive_lab_resources.yaml
    ├── parameters.json
    └── README.md
```

## Deployment Options

### Option 1: Single Account Stack

**Best for:** Testing, POC, accounts not in AWS Organizations

Deploy Britive integration to a single AWS account using standard CloudFormation stacks.

**Templates:**
- `britive_integration_resources.yaml` - Core integration only (SAML provider + integration role)
- `britive_integration_with_roles.yaml` - Core integration + sample JIT roles

**Quick deploy:**
```bash
cd single-account-stack
aws cloudformation create-stack \
  --stack-name britive-integration \
  --template-body file://britive_integration_resources.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

[Full documentation](single-account-stack/README.md)

---

### Option 2: StackSet Templates

**Best for:** Multi-account deployments, AWS Organizations

Deploy Britive integration across multiple accounts using CloudFormation StackSets. Supports automatic deployment to new accounts.

**Templates:**
- `britive_integration_resources_stackset.yaml` - Core integration only
- `britive_integration_with_roles_stackset.yaml` - Core integration + sample JIT roles

**Key features:**
- Deploy to all accounts in an OU with a single command
- Auto-deployment to new accounts joining the organization
- Centralized management and updates

**Quick deploy:**
```bash
cd stackset-templates
./generate-parameters.sh mycompany britive-saml-metadata.xml true

aws cloudformation create-stack-set \
  --stack-set-name britive-integration \
  --template-body file://britive_integration_resources_stackset.yaml \
  --parameters file://parameters.json \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --capabilities CAPABILITY_NAMED_IAM
```

[Full documentation](stackset-templates/README.md)

---

### Option 3: Organization StackSet (Nested Stacks)

**Best for:** Complete organization deployment including management account

Uses nested stacks to deploy to both the management account (which StackSets cannot target) and all member accounts via StackSet.

**Templates:**
- `deploy_britive_integration_resources.yaml` - Main template with nested stack + StackSet
- `britive_integration_resources.yaml` - Reusable template (uploaded to S3)

**Key features:**
- Single deployment covers entire organization
- Management account included via nested stack
- Member accounts via StackSet

**Quick deploy:**
```bash
cd organization-stackset
# Upload nested template to S3 first
aws s3 cp britive_integration_resources.yaml s3://my-bucket/

aws cloudformation deploy \
  --template-file deploy_britive_integration_resources.yaml \
  --stack-name britive-organization-integration \
  --parameter-overrides file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

[Full documentation](organization-stackset/README.md)

---

### Option 4: Full Lab Setup

**Best for:** Demos, training, proof-of-concept environments

Creates a complete demo environment with VPC, EC2 instances (Linux/Windows), RDS database, and sample JIT roles.

**Resources created:**
- Britive SAML integration
- VPC with public subnets
- Linux EC2 instance (SSH demos)
- Windows EC2 instance (RDP demos)
- RDS MySQL database
- Sample JIT roles (ReadOnly, PowerUser, EC2Admin, S3Admin)

**Warning:** This template uses permissive security groups (0.0.0.0/0) for demo purposes. Do NOT use in production.

**Estimated cost:** ~$52/month (mostly EC2 and RDS)

[Full documentation](full-lab-setup/README.md)

---

## Prerequisites

All deployment options require:

1. **Britive Tenant Name**: Your tenant identifier (e.g., `mycompany` from `mycompany.britive-app.com`)

2. **SAML Metadata Document**: Download from your Britive tenant
   - Navigate to: Settings > Identity Providers > AWS > Download SAML Metadata
   - Save the XML file

3. **IAM Permissions**: Ability to create IAM roles, SAML providers, and CloudFormation resources

4. **AWS CLI** (for CLI deployments): Version 2.x recommended

## Resources Created

All templates create these core resources:

| Resource | Name Pattern | Purpose |
|----------|--------------|---------|
| SAML Provider | `britive-<tenant>` | Federated authentication from Britive |
| Integration Role | `britive-<tenant>-integration-role` | Allows Britive to discover IAM roles |

**Integration Role Permissions:**
- `IAMReadOnlyAccess` - List IAM roles and policies
- `AWSOrganizationsReadOnlyAccess` - Query organization structure
- AWS Invalidation policy (optional) - Manage deny policies for credential revocation

## Comparison Matrix

| Feature | Single Account | StackSets | Org StackSet | Full Lab |
|---------|---------------|-----------|--------------|----------|
| **Scope** | 1 account | Multiple accounts | Entire org | 1 account |
| **Management account** | Manual | Manual | Included | N/A |
| **Auto-deploy to new accounts** | No | Yes | Yes | No |
| **Sample JIT roles** | Optional | Optional | No | Yes |
| **Demo resources (EC2/RDS)** | No | No | No | Yes |
| **Complexity** | Low | Medium | High | Medium |
| **Production ready** | Yes | Yes | Yes | No |

## Security Considerations

1. **SAML Metadata**: Contains certificates - store securely, don't commit to public repos

2. **Integration Role**: Has read-only access to IAM. The AWS Invalidation feature adds write permissions scoped to `britive/managed/*` policy path only

3. **JIT Roles**: Sample roles use AWS managed policies. Customize for production use

4. **Full Lab Setup**: Uses 0.0.0.0/0 security groups - demo only, not production

## Updating Templates

When SAML certificates rotate or configuration changes:

**Single Account:**
```bash
aws cloudformation update-stack \
  --stack-name britive-integration \
  --template-body file://britive_integration_resources.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

**StackSets:**
```bash
aws cloudformation update-stack-set \
  --stack-set-name britive-integration \
  --template-body file://britive_integration_resources_stackset.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Invalid SAML metadata" | Malformed XML or missing header | Verify complete XML including `<?xml version="1.0"?>` |
| "Role already exists" | Duplicate deployment | Delete existing role or use different tenant name |
| "Insufficient permissions" | Missing IAM permissions | Grant CloudFormation and IAM permissions |
| "StackSet deployment failed" | Trusted access not enabled | Enable StackSets service access in Organizations |

### Validate SAML Metadata

```bash
xmllint --noout britive-saml-metadata.xml && echo "Valid" || echo "Invalid"
```

### Check Stack Status

```bash
# Single stack
aws cloudformation describe-stacks --stack-name britive-integration

# StackSet instances
aws cloudformation list-stack-instances --stack-set-name britive-integration
```

## Additional Resources

- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS CloudFormation StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
- [AWS IAM SAML Federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_saml.html)
- [Britive Documentation](https://docs.britive.com)

## Support

- **CloudFormation issues**: Check AWS documentation or open an issue in this repository
- **Britive integration**: Contact Britive support or your account team
- **AWS permissions**: Consult AWS IAM documentation or AWS support
