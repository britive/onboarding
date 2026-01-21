# Britive Integration - Organization-Wide Deployment with Nested Stacks

This directory contains a CloudFormation deployment method that uses nested stacks to deploy Britive integration resources across your entire AWS Organization, including the management account.

## Overview

This deployment creates a CloudFormation stack with two components:

1. **Nested Stack**: Deploys integration resources to the organization management account (since StackSets cannot deploy to the management account)
2. **StackSet Resource**: Deploys integration resources to all member accounts in the AWS Organization

## When to Use This Method

Use this organization-stackset deployment when:

- You need to deploy Britive integration to the **entire AWS Organization** including the management account
- You want a single deployment that handles both management and member accounts
- You prefer a nested stack approach over separate deployments

**Alternative approaches:**

- For **modern StackSet deployments** without nested stacks, see [StackSet Templates](../stackset-templates/)
- For **single account** testing or POC, see [Single Account Stack](../single-account-stack/)
- For **demo environments**, see [Full Lab Setup](../full-lab-setup/)

## Templates

- **deploy_britive_integration_resources.yaml**: Main template that creates nested stack and StackSet
- **britive_integration_resources.yaml**: Reusable template for actual integration resources (uploaded to S3)

## Prerequisites

### Required Setup

1. **AWS Organization**: Must be enabled in your management account
2. **StackSets**: Ensure StackSets is enabled for your AWS Organization
3. **S3 Bucket**: Create or use an existing S3 bucket in the management account
   - Bucket must NOT be public
   - No cross-account access required
   - Used to host the nested template file
4. **IAM Permissions**: Must have permissions to create CloudFormation stacks, nested stacks, StackSets, and IAM resources

### Britive Information Needed

Before deployment, obtain from your Britive tenant:

1. **Tenant Name**: Your Britive tenant name (e.g., `mycompany` from `mycompany.britive-app.com`)
2. **SAML Metadata Document**: Download from Britive
   - Navigate to: Admin → Security → SAML Configurations → Download SAML Metadata
   - Save the XML file

## Deployment Steps

### Step 1: Prepare S3 Bucket

Create an S3 bucket (or use existing) in the management account:

```bash
# Create S3 bucket (if needed)
aws s3 mb s3://my-britive-templates --region us-east-1

# Upload the integration resources template
aws s3 cp britive_integration_resources.yaml s3://my-britive-templates/

# Verify upload
aws s3 ls s3://my-britive-templates/
```

### Step 2: Configure Parameters

Edit the `parameters.json` file with your specific values:

```json
[
  {
    "ParameterKey": "TenantName",
    "ParameterValue": "mycompany"
  },
  {
    "ParameterKey": "SamlMetadataDocumentXmlContent",
    "ParameterValue": "<?xml version=\"1.0\"?>..."
  },
  {
    "ParameterKey": "DeployAwsInvalidationFeature",
    "ParameterValue": "true"
  },
  {
    "ParameterKey": "S3BucketName",
    "ParameterValue": "my-britive-templates"
  },
  {
    "ParameterKey": "S3Key",
    "ParameterValue": "britive_integration_resources.yaml"
  }
]
```

**Parameter descriptions:**

| Parameter | Description | Example |
| ----------- | ------------- | --------- |
| `TenantName` | Britive tenant name (without .britive-app.com) | `mycompany` |
| `SamlMetadataDocumentXmlContent` | Full SAML metadata XML content | `<?xml version="1.0"?>...` |
| `DeployAwsInvalidationFeature` | Enable AWS invalidation permissions | `true` or `false` |
| `S3BucketName` | S3 bucket containing the nested template | `my-britive-templates` |
| `S3Key` | S3 key/path to the template file | `britive_integration_resources.yaml` |

**Tip**: Use the helper script from the StackSet templates directory to generate the parameters file:

```bash
# Generate parameters with properly escaped SAML metadata
../stackset-templates/generate-parameters.sh mycompany britive-saml-metadata.xml true > parameters-base.json

# Then manually add S3 bucket parameters
```

### Step 3: Deploy the Stack

#### Via AWS CLI

```bash
aws cloudformation deploy \
  --template-file deploy_britive_integration_resources.yaml \
  --stack-name britive-organization-integration \
  --parameter-overrides file://parameters.json \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM

# Monitor deployment
aws cloudformation describe-stacks \
  --stack-name britive-organization-integration \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```

#### Via AWS Console

1. Navigate to **CloudFormation** in the AWS Console
2. Click **Create stack** → **With new resources**
3. Upload `deploy_britive_integration_resources.yaml`
4. Enter stack name: `britive-organization-integration`
5. Fill in the parameters:
   - Tenant name
   - SAML metadata content
   - S3 bucket name and key
   - Enable/disable invalidation feature
6. Acknowledge IAM resource creation
7. Click **Create stack**

### Step 4: Verify Deployment

Once the stack deployment is complete, verify the resources:

```bash
# Get stack outputs
aws cloudformation describe-stacks \
  --stack-name britive-organization-integration \
  --region us-east-1 \
  --output table \
  --query 'Stacks[0].Outputs'

# Check nested stack status
aws cloudformation describe-stacks \
  --region us-east-1 \
  --query 'Stacks[?contains(StackName, `britive`)].[StackName,StackStatus]' \
  --output table

# List StackSet instances
aws cloudformation list-stack-instances \
  --stack-set-name britive-stackset \
  --query 'Summaries[].[Account,Region,Status]' \
  --output table
```

### Step 5: Verify IAM Resources

Check that SAML provider and integration role were created:

```bash
# In the management account
aws iam get-saml-provider \
  --saml-provider-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):saml-provider/britive-mycompany

aws iam get-role \
  --role-name britive-mycompany-integration-role

# List all stack instances across member accounts
aws cloudformation list-stack-instances \
  --stack-set-name britive-stackset
```

## What Gets Deployed

### In the Management Account (via Nested Stack)

- SAML Identity Provider: `britive-<tenant-name>`
- Integration Role: `britive-<tenant-name>-integration-role`
  - Managed Policies: IAMReadOnlyAccess, AWSOrganizationsReadOnlyAccess
  - Optional inline policy for AWS invalidation feature

### In Member Accounts (via StackSet)

- SAML Identity Provider: `britive-<tenant-name>`
- Integration Role: `britive-<tenant-name>-integration-role`
  - Managed Policies: IAMReadOnlyAccess
  - Optional inline policy for AWS invalidation feature

## Updating the Deployment

To update SAML metadata or change parameters:

```bash
# Update parameters.json with new values

# Update the stack
aws cloudformation deploy \
  --template-file deploy_britive_integration_resources.yaml \
  --stack-name britive-organization-integration \
  --parameter-overrides file://parameters.json \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM

# Monitor update
aws cloudformation wait stack-update-complete \
  --stack-name britive-organization-integration \
  --region us-east-1
```

## Deleting the Deployment

To remove all Britive integration resources:

```bash
# Delete the main stack (this will delete nested stack and StackSet instances)
aws cloudformation delete-stack \
  --stack-name britive-organization-integration \
  --region us-east-1

# Monitor deletion
aws cloudformation wait stack-delete-complete \
  --stack-name britive-organization-integration \
  --region us-east-1
```

**Note**: The StackSet instances will be automatically deleted when the parent stack is deleted.

## Troubleshooting

### S3 Bucket Access Issues

**Error**: "Unable to fetch template from S3"

**Solutions**:

1. Verify bucket exists and template is uploaded:

   ```bash
   aws s3 ls s3://my-britive-templates/
   ```

2. Ensure CloudFormation has access to the bucket (should work automatically for same-account buckets)

### Nested Stack Creation Failed

**Error**: "Nested stack creation failed"

**Solutions**:

1. Check the nested stack events for specific errors:

   ```bash
   aws cloudformation describe-stack-events \
     --stack-name <nested-stack-name> \
     --max-items 20
   ```

2. Verify the S3 template URL is correct in the main template

### StackSet Deployment Failed

**Error**: "Failed to create StackSet instances"

**Solutions**:

1. Ensure StackSets is enabled for AWS Organizations:

   ```bash
   aws organizations enable-aws-service-access \
     --service-principal member.org.stacksets.cloudformation.amazonaws.com
   ```

2. Check StackSet operation status:

   ```bash
   aws cloudformation list-stack-set-operations \
     --stack-set-name britive-stackset
   ```

### Resource Already Exists

**Error**: "Role britive-mycompany-integration-role already exists"

**Solutions**:

- Delete existing resources manually before redeployment
- Or use CloudFormation import to bring existing resources under stack management

## Comparison with Other Deployment Methods

| Feature | Organization StackSet (This) | StackSet Templates | Single Account |
| --------- | ------------------------------ | ------------------- | ---------------- |
| **Management Account** | ✅ Included via nested stack | ❌ Manual deployment needed | N/A |
| **Member Accounts** | ✅ Via StackSet | ✅ Via StackSet | ❌ One at a time |
| **Single Deployment** | ✅ Yes | ❌ Two separate deployments | ❌ Per account |
| **Complexity** | High (nested stacks) | Medium | Low |
| **Best For** | Complete org automation | Modern StackSet approach | Testing/POC |

## Next Steps

After successful deployment:

1. **Configure Britive**:
   - Add AWS accounts to your Britive tenant
   - Use the integration role ARN from stack outputs
   - Create profiles for access management

2. **Test Integration**:
   - Request access through Britive
   - Verify SAML SSO to AWS Console
   - Test CLI/API access

3. **Monitor Usage**:
   - Enable CloudTrail for role assumptions
   - Review access logs in Britive
   - Set up alerting for unusual access patterns

## Additional Resources

- [CloudFormation Nested Stacks](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html)
- [CloudFormation StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
- [AWS Organizations](https://docs.aws.amazon.com/organizations/)
- [Britive Documentation](https://docs.britive.com)

## Support

For issues with:

- **CloudFormation templates**: Review AWS CloudFormation documentation or open an issue
- **Britive integration**: Contact Britive support or your account team
- **AWS Organizations**: Consult AWS Organizations documentation or AWS support
