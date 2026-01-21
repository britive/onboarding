# Britive Integration CloudFormation Templates (Single Account)

This directory contains CloudFormation templates for deploying Britive integration resources to a single AWS account.

## Templates

1. **britive_integration_resources.yaml** - Deploys the core Britive integration resources (SAML provider and integration role)
2. **britive_integration_with_roles.yaml** - Deploys core integration resources plus sample JIT roles (ReadOnly, PowerUser, EC2 Admin, S3 Admin)

## When to Use These Templates

Use single-account templates when:

- Testing Britive integration in a single AWS account
- Setting up a proof-of-concept (POC)
- Deploying to accounts not part of AWS Organizations
- You need fine-grained control over each account deployment

**For organization-wide deployment** across multiple accounts, see the [StackSet templates](../stackset-templates/).

**For complete demo environments**, see the [Full Lab Setup](../full-lab-setup/).

## Table of Contents

- [Prerequisites](#prerequisites)
- [Getting SAML Metadata](#getting-saml-metadata)
- [Deployment via AWS Console](#deployment-via-aws-console)
- [Deployment via AWS CLI](#deployment-via-aws-cli)
- [Verifying Deployment](#verifying-deployment)
- [Updating the Stack](#updating-the-stack)
- [Deleting the Stack](#deleting-the-stack)

---

## Prerequisites

### Required IAM Permissions

You need permissions to create IAM resources in the target account:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateStack",
        "cloudformation:DescribeStacks",
        "cloudformation:UpdateStack",
        "cloudformation:DeleteStack",
        "iam:CreateRole",
        "iam:CreateSAMLProvider",
        "iam:CreatePolicy",
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy",
        "iam:GetRole",
        "iam:GetSAMLProvider"
      ],
      "Resource": "*"
    }
  ]
}
```

### Britive Information Needed

1. **Tenant Name**: Your Britive tenant name (e.g., if your URL is `mycompany.britive-app.com`, the tenant name is `mycompany`)
2. **SAML Metadata Document**: Download the SAML metadata XML from your Britive tenant

---

## Getting SAML Metadata

### Step 1: Download from Britive

1. Log into your Britive tenant at `https://<your-tenant>.britive-app.com`
2. Navigate to **Settings** (gear icon) → **Identity Providers**
3. Find **AWS** in the list
4. Click **Download SAML Metadata** or **View Metadata**
5. Save the XML file (e.g., `britive-saml-metadata.xml`)

### Step 2: Verify the File

The SAML metadata should look like this:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" entityID="https://your-tenant.britive-app.com">
  <IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <KeyDescriptor use="signing">
      <KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#">
        <X509Data>
          <X509Certificate>MIIDdDCCAlygAwIBAgIGAXm...</X509Certificate>
        </X509Data>
      </KeyInfo>
    </KeyDescriptor>
    <!-- ... more configuration ... -->
  </IDPSSODescriptor>
</EntityDescriptor>
```

---

## Deployment via AWS Console

### Step 1: Navigate to CloudFormation

1. Sign in to the **AWS Management Console**
2. Navigate to **CloudFormation** service
3. Click **Create stack** → **With new resources (standard)**

### Step 2: Specify Template

1. **Prerequisite - Prepare template**: Select **Template is ready**
2. **Specify template**: Select **Upload a template file**
3. Click **Choose file** and select:
   - `britive_integration_resources.yaml` (core only), or
   - `britive_integration_with_roles.yaml` (core + sample roles)
4. Click **Next**

### Step 3: Specify Stack Details

1. **Stack name**: Enter a name (e.g., `britive-integration`)

2. **Parameters**:

   - **Britive Tenant Name**: Enter your tenant name (e.g., `mycompany`)

   - **SAML Metadata Document XML**:

     **Method 1: Copy-Paste (Recommended)**
     - Open your `britive-saml-metadata.xml` file in a text editor
     - Select ALL content (Ctrl+A / Cmd+A)
     - Copy (Ctrl+C / Cmd+C)
     - Paste into the AWS Console parameter field
     - ⚠️ **Important**: Include the entire XML including `<?xml version="1.0"?>` header

     **Method 2: Single-Line Format**

     If you encounter issues with multi-line paste:
     ```bash
     # On your terminal, create a single-line version
     cat britive-saml-metadata.xml | tr -d '\n' | tr -s ' '
     ```
     Copy the output and paste into the Console

   - **Enable AWS Invalidation Feature**: Select `true` or `false` (default: `true`)

3. Click **Next**

### Step 4: Configure Stack Options

1. **Tags** (Optional): Add tags for organization
   - Example: Key=`Project`, Value=`BritiveIntegration`

2. **Permissions** (Optional): Use an existing IAM role or leave default

3. **Stack failure options**: Choose rollback behavior

4. Click **Next**

### Step 5: Review and Create

1. Review all settings

2. **Capabilities**:
   - ✅ Check **I acknowledge that AWS CloudFormation might create IAM resources with custom names**

3. Click **Submit**

### Step 6: Monitor Deployment

1. You'll see the stack in **CREATE_IN_PROGRESS** status
2. Click the **Events** tab to monitor progress
3. Wait for status to change to **CREATE_COMPLETE** (typically 1-2 minutes)
4. If any errors occur, check the Events tab for details

---

## Deployment via AWS CLI

### Prerequisites

1. Install and configure AWS CLI v2:
   ```bash
   aws --version  # Should be 2.x or higher
   aws configure  # Set up your credentials
   ```

2. Verify you're in the correct account:
   ```bash
   aws sts get-caller-identity
   ```

### Method 1: Using the Helper Script (Easiest)

We provide a helper script to generate the parameters file:

```bash
# Download the helper script (if not already in the repo)
cd /path/to/cloudformation/aws

# Make it executable
chmod +x stackset-templates/generate-parameters.sh

# Generate parameters.json
./stackset-templates/generate-parameters.sh mycompany britive-saml-metadata.xml true

# Deploy the stack
aws cloudformation create-stack \
  --stack-name britive-integration \
  --template-body file://single-account-stack/britive_integration_resources.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

### Method 2: Manual Parameters File

Create `parameters.json` manually:

```bash
# Use jq to properly escape the SAML metadata
SAML_CONTENT=$(cat britive-saml-metadata.xml | jq -Rs .)

# Create parameters file
cat > parameters.json << EOF
[
  {
    "ParameterKey": "TenantName",
    "ParameterValue": "mycompany"
  },
  {
    "ParameterKey": "SamlMetadataDocumentXmlContent",
    "ParameterValue": ${SAML_CONTENT}
  },
  {
    "ParameterKey": "DeployAwsInvalidationFeature",
    "ParameterValue": "true"
  }
]
EOF

# Deploy
aws cloudformation create-stack \
  --stack-name britive-integration \
  --template-body file://single-account-stack/britive_integration_resources.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

### Method 3: Inline Parameters (Quick Testing)

⚠️ Not recommended for production (exposes parameters in command history)

```bash
SAML_METADATA=$(cat britive-saml-metadata.xml)

aws cloudformation create-stack \
  --stack-name britive-integration \
  --template-body file://single-account-stack/britive_integration_resources.yaml \
  --parameters \
    ParameterKey=TenantName,ParameterValue=mycompany \
    ParameterKey=SamlMetadataDocumentXmlContent,ParameterValue="$SAML_METADATA" \
    ParameterKey=DeployAwsInvalidationFeature,ParameterValue=true \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

### Monitor Deployment

```bash
# Check stack status
aws cloudformation describe-stacks \
  --stack-name britive-integration \
  --query 'Stacks[0].StackStatus' \
  --output text

# Watch stack events
aws cloudformation describe-stack-events \
  --stack-name britive-integration \
  --max-items 20

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name britive-integration

echo "Stack deployment completed!"
```

---

## Verifying Deployment

### Via AWS Console

1. Go to **CloudFormation** → **Stacks**
2. Click on your stack (e.g., `britive-integration`)
3. Check the **Outputs** tab for created resource ARNs
4. Navigate to **IAM** → **Roles** to verify:
   - `britive-<tenant>-integration-role`
   - Sample roles (if using the `with_roles` template)
5. Navigate to **IAM** → **Identity providers** to verify:
   - `britive-<tenant>` SAML provider

### Via AWS CLI

```bash
# List stack outputs
aws cloudformation describe-stacks \
  --stack-name britive-integration \
  --query 'Stacks[0].Outputs' \
  --output table

# Verify IAM role exists
aws iam get-role \
  --role-name britive-mycompany-integration-role

# Verify SAML provider exists
aws iam get-saml-provider \
  --saml-provider-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):saml-provider/britive-mycompany
```

---

## Updating the Stack

### When to Update

- SAML metadata certificate rotation
- Enabling/disabling AWS invalidation feature
- Template modifications

### Via AWS Console

1. Go to **CloudFormation** → **Stacks**
2. Select your stack
3. Click **Update**
4. Choose **Replace current template** or **Use current template**
5. Update parameters as needed
6. Follow the wizard to complete the update

### Via AWS CLI

```bash
# Regenerate parameters if SAML metadata changed
../stackset-templates/generate-parameters.sh mycompany new-britive-saml-metadata.xml true

# Update the stack
aws cloudformation update-stack \
  --stack-name britive-integration \
  --template-body file://britive_integration_resources.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM

# Monitor update
aws cloudformation wait stack-update-complete \
  --stack-name britive-integration
```

---

## Deleting the Stack

### Via AWS Console

1. Go to **CloudFormation** → **Stacks**
2. Select your stack
3. Click **Delete**
4. Confirm deletion
5. Monitor the deletion process in the Events tab

### Via AWS CLI

```bash
# Delete the stack
aws cloudformation delete-stack \
  --stack-name britive-integration

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
  --stack-name britive-integration

echo "Stack deleted successfully!"
```

---

## Parameters Reference

| Parameter | Description | Example | Required |
|-----------|-------------|---------|----------|
| `TenantName` | Britive tenant name (without .britive-app.com) | `mycompany` | Yes |
| `SamlMetadataDocumentXmlContent` | Full XML content from SAML metadata file | `<?xml version="1.0"?>...` | Yes |
| `DeployAwsInvalidationFeature` | Enable AWS invalidation permissions | `true` or `false` | No (default: `true`) |

---

## Resources Created

### Core Resources (both templates)

- **SAML Provider**: `britive-<tenant-name>`
- **Integration Role**: `britive-<tenant-name>-integration-role`
  - Managed Policies: IAMReadOnlyAccess, AWSOrganizationsReadOnlyAccess
  - Inline Policy (optional): AWS Invalidation permissions

### Additional Roles (with_roles template only)

- **ReadOnly Role**: `Readonly-admin-role`
  - Policy: ReadOnlyAccess
- **PowerUser Role**: `Poweruser-role`
  - Policy: PowerUserAccess
- **EC2 Admin Role**: `EC2-Fullaccess-role`
  - Policy: AmazonEC2FullAccess
- **S3 Admin Role**: `S3-Fullaccess-role`
  - Policy: AmazonS3FullAccess

---

## Troubleshooting

### SAML Metadata Issues

**Problem**: "Invalid SAML metadata document" error

**Solutions**:
1. Verify the XML file is well-formed:
   ```bash
   xmllint --noout britive-saml-metadata.xml && echo "Valid" || echo "Invalid"
   ```
2. Ensure you copied the entire content including the XML header
3. Check for special characters that need escaping in JSON
4. Download fresh SAML metadata from Britive

### Role Already Exists

**Problem**: "Role britive-mycompany-integration-role already exists"

**Solutions**:
1. Delete the existing role manually:
   ```bash
   aws iam delete-role --role-name britive-mycompany-integration-role
   ```
2. Or use a different tenant name in parameters

### Insufficient Permissions

**Problem**: "User is not authorized to perform: iam:CreateRole"

**Solutions**:
1. Verify you have IAM permissions (see [Prerequisites](#prerequisites))
2. Check you're in the correct AWS account
3. Contact your AWS administrator to grant necessary permissions

### Stack Stuck in CREATE_IN_PROGRESS

**Problem**: Stack is taking longer than expected

**Solutions**:
1. Check the Events tab for error messages
2. Common causes:
   - IAM permission issues
   - Service limits reached
   - Invalid SAML metadata
3. Cancel and retry if needed:
   ```bash
   aws cloudformation cancel-update-stack --stack-name britive-integration
   ```

---

## Next Steps

After successful deployment:

1. **Configure Britive**:
   - Add this AWS account to your Britive tenant
   - Create profiles for the deployed roles
   - Set up access policies

2. **Test Integration**:
   - Request access through Britive
   - Verify SSO login to AWS Console works
   - Test CLI/API access with temporary credentials

3. **Deploy to Additional Accounts**:
   - For multiple accounts, consider using [StackSets](../stackset-templates/)
   - Or repeat this process for each account

---

## Additional Resources

- [CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [Britive Documentation](https://docs.britive.com)
- [AWS IAM SAML Federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_saml.html)
- [StackSets for Multi-Account Deployment](../stackset-templates/README.md)

---

## Security Best Practices

1. **Protect SAML Metadata**: Don't commit SAML metadata files to version control
2. **Use Parameter Store**: Consider storing SAML metadata in AWS Systems Manager Parameter Store
3. **Regular Rotation**: Rotate SAML certificates according to your security policy
4. **Least Privilege**: Only enable AWS invalidation feature if needed
5. **Monitor Access**: Enable CloudTrail logging for IAM role assumptions
6. **Tag Resources**: Use consistent tagging for cost allocation and compliance

---

## Cost Considerations

- CloudFormation stacks have no additional cost
- IAM resources (roles, policies, SAML providers) are free
- No ongoing costs for this infrastructure
- You only pay for resources accessed using the created roles

---

## Support

For issues with:
- **CloudFormation templates**: Check AWS CloudFormation documentation or open an issue
- **Britive integration**: Contact Britive support or your Britive account team
- **AWS permissions**: Review AWS IAM documentation or contact AWS support
