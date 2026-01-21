# Britive AWS Onboarding with CloudFormation

This repository provides CloudFormation templates and scripts to integrate AWS accounts and organizations with the Britive platform. Deploy Britive integration resources to single accounts, multiple accounts, or entire AWS Organizations.

## Overview

Britive's CloudFormation templates automate the setup and configuration of secure, just-in-time (JIT) privileged access management (PAM) using Zero Standing Privilege (ZSP) principles. These templates create the necessary IAM roles, SAML providers, and policies required for Britive integration.

## Benefits

- **Automation**: Eliminate manual deployment steps and reduce human error
- **Consistency**: Ensure uniform security configurations across all AWS environments
- **Scalability**: Easily scale from single accounts to organization-wide deployments
- **Security**: Implement least-privilege access with JIT elevation and federated authentication
- **Compliance**: Maintain audit trails and enforce security policies consistently

## Deployment Options

Choose the deployment method that best fits your needs:

| Deployment Method | Use Case | Best For |
| ------------------- | ---------- | ---------- |
| [**Single Account Stack**](aws/single-account-stack/) | Deploy to one AWS account | Testing, POC, standalone accounts |
| [**StackSet Templates**](aws/stackset-templates/) | Deploy to multiple accounts via StackSets | Production, organization-wide deployment |
| [**Organization StackSet**](aws/organization-stackset/) | Deploy to entire organization with nested stacks | Complete org automation including management account |
| [**Full Lab Setup**](aws/full-lab-setup/) | Complete demo environment with VPC, EC2, RDS | Demo, training, sandbox environments |

## Quick Start

### Prerequisites

Before deploying any templates, you'll need:

1. **Britive Tenant**: An active Britive tenant (e.g., `mycompany.britive-app.com`)
2. **SAML Metadata**: Download SAML metadata XML from your Britive tenant
   - Navigate to: Settings → Identity Providers → AWS → Download SAML Metadata
3. **AWS Permissions**: IAM permissions to create CloudFormation stacks, IAM roles, and SAML providers
4. **AWS CLI** (optional): AWS CLI v2 installed and configured for command-line deployments

### Choose Your Path

#### For Single Account Testing

Start with [Single Account Stack](aws/single-account-stack/) to deploy core Britive integration resources to one account.

#### For Organization-Wide Deployment

Use [StackSet Templates](aws/stackset-templates/) to deploy across multiple accounts with centralized management and automatic deployment to new accounts.

#### For Legacy Organization Deployment

Use [Organization StackSet](aws/organization-stackset/) if you need to include the management account via nested stacks.

#### For Demo/Lab Environment

Deploy [Full Lab Setup](aws/full-lab-setup/) to create a complete demo environment with sample resources.

## What Gets Deployed

### Core Integration Resources

All deployment methods create these essential resources:

- **SAML Identity Provider**: `britive-<tenant-name>`
- **Integration Role**: `britive-<tenant-name>-integration-role`
  - Permissions: IAM ReadOnly, AWS Organizations ReadOnly
  - Optional: AWS Invalidation feature (managed policy write permissions)

### Optional Sample Roles

Some templates include sample JIT roles for common use cases:

- **ReadOnly Role**: Read-only access across AWS services
- **PowerUser Role**: PowerUser access (application development)
- **EC2 Admin Role**: Full EC2 management
- **S3 Admin Role**: Full S3 management

## Directory Structure

```text
cloudformation/
├── README.md                          # This file
└── aws/
    ├── single-account-stack/          # Single account deployment
    │   ├── britive_integration_resources.yaml
    │   ├── britive_integration_with_roles.yaml
    │   └── README.md
    ├── stackset-templates/            # Multi-account StackSet deployment
    │   ├── britive_integration_resources_stackset.yaml
    │   ├── britive_integration_with_roles_stackset.yaml
    │   ├── generate-parameters.sh
    │   └── README.md
    ├── organization-stackset/         # Organization-wide nested stack deployment
    │   ├── deploy_britive_integration_resources.yaml
    │   ├── britive_integration_resources.yaml
    │   └── README.md
    └── full-lab-setup/                # Complete demo environment
        ├── britive_lab_resources.yaml
        └── README.md
```

## Next Steps After Deployment

After successfully deploying the CloudFormation templates:

1. **Add AWS Account to Britive**:
   - Log into your Britive tenant
   - Navigate to Applications → Add Application → AWS
   - Enter your AWS account details and integration role ARN

2. **Create Profiles**:
   - Define access profiles for the deployed IAM roles
   - Set up approval workflows and access policies

3. **Configure Access Policies**:
   - Assign users and groups to profiles
   - Configure time-based and conditional access

4. **Test Integration**:
   - Request access through Britive
   - Verify SSO to AWS Console
   - Test CLI/API access with temporary credentials

## Security Best Practices

- **Protect SAML Metadata**: Never commit SAML metadata files to version control
- **Use Parameter Store**: Store sensitive parameters in AWS Systems Manager Parameter Store
- **Regular Rotation**: Rotate SAML certificates according to your security policy
- **Least Privilege**: Only enable AWS invalidation feature if required
- **Enable CloudTrail**: Monitor all IAM role assumptions and API calls
- **Tag Resources**: Use consistent tagging for cost allocation and compliance tracking

## Cost Considerations

- CloudFormation stacks and StackSets: **No charge**
- IAM resources (roles, policies, SAML providers): **No charge**
- No ongoing infrastructure costs for Britive integration
- You only pay for AWS resources accessed using the created roles

## Support and Documentation

- **Britive Documentation**: [docs.britive.com](https://docs.britive.com)
- **AWS CloudFormation**: [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- **AWS IAM SAML**: [IAM SAML Federation Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_saml.html)
- **Britive Support**: Contact your Britive account team

## Additional Resources

- [AWS Organizations Documentation](https://docs.aws.amazon.com/organizations/)
- [CloudFormation StackSets Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)

---

**Note**: These templates are designed for the initial onboarding of AWS accounts into Britive. Once onboarded, all privileged access management is handled through the Britive platform.
