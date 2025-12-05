# Britive Integration CloudFormation StackSets

This directory contains CloudFormation StackSet templates that allow you to deploy Britive integration resources across multiple AWS accounts at the organizational unit (OU) or folder level.

## Templates

1. **britive_integration_resources_stackset.yaml** - Deploys the core Britive integration resources (SAML provider and integration role)
2. **britive_integration_with_roles_stackset.yaml** - Deploys core integration resources plus sample JIT roles (ReadOnly, PowerUser, EC2 Admin, S3 Admin)

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment via AWS Console (UI)](#deployment-via-aws-console-ui)
- [Deployment via AWS CLI](#deployment-via-aws-cli)
- [Monitoring and Management](#monitoring-and-management)
- [Updating StackSets](#updating-stacksets)
- [Deleting StackSets](#deleting-stacksets)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### AWS Organization Setup
- AWS Organizations must be enabled in your management account
- You must be logged into the **management account** or a **delegated administrator account**
- Service-managed permissions must be enabled for StackSets (recommended)

### Required IAM Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateStackSet",
        "cloudformation:CreateStackInstances",
        "cloudformation:DescribeStackSet",
        "cloudformation:ListStackInstances",
        "cloudformation:UpdateStackSet",
        "cloudformation:DeleteStackInstances",
        "cloudformation:DeleteStackSet",
        "organizations:ListRoots",
        "organizations:ListOrganizationalUnitsForParent",
        "organizations:ListAccounts",
        "organizations:DescribeOrganization"
      ],
      "Resource": "*"
    }
  ]
}
```

### Britive Information Needed

Before deployment, gather the following from your Britive tenant:

1. **Tenant Name**: Your Britive tenant name (e.g., if your URL is `mycompany.britive-app.com`, the tenant name is `mycompany`)

2. **SAML Metadata Document**: Download the SAML metadata XML from your Britive tenant
   - Log into Britive → Settings → Identity Providers → AWS → Download SAML Metadata
   - Save the file (e.g., `britive-saml-metadata.xml`)

#### How to Obtain SAML Metadata from Britive

1. Log into your Britive tenant at `https://<your-tenant>.britive-app.com`
2. Navigate to **Settings** (gear icon)
3. Go to **Identity Providers** section
4. Find **AWS** in the list
5. Click **Download SAML Metadata** or **View Metadata**
6. Save the XML file to your local machine

**Example SAML metadata structure:**
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

### Enable StackSets Service-Managed Permissions (First Time Only)

If this is your first time using StackSets with service-managed permissions, you need to enable trusted access:

**Via AWS Console:**
1. Go to **AWS Organizations** console
2. Navigate to **Services** → **Trusted access**
3. Find **CloudFormation StackSets** and click **Enable trusted access**

**Via AWS CLI:**
```bash
aws organizations enable-aws-service-access \
  --service-principal member.org.stacksets.cloudformation.amazonaws.com
```

---

## Deployment via AWS Console (UI)

### Step 1: Navigate to CloudFormation StackSets

1. Sign in to the **AWS Management Console** with your management account
2. Navigate to **CloudFormation** service
3. In the left sidebar, click **StackSets**
4. Click **Create StackSet** button

### Step 2: Choose Template

1. **Prerequisite - Prepare template**: Select **Template is ready**
2. **Specify template**: Select **Upload a template file**
3. Click **Choose file** and select either:
   - `britive_integration_resources_stackset.yaml` (core resources only), or
   - `britive_integration_with_roles_stackset.yaml` (core + sample roles)
4. Click **Next**

### Step 3: Specify StackSet Details

1. **StackSet name**: Enter a name (e.g., `britive-integration-stackset`)
2. **StackSet description**: (Optional) Enter a description
3. **Parameters**: Fill in the required parameters:
   - **Britive Tenant Name**: Enter your tenant name (e.g., `mycompany`)
   - **SAML Metadata Document XML**:

     **Method 1: Copy-Paste (Recommended for Console)**
     - Open your downloaded SAML metadata XML file in a text editor
     - Select ALL content (Ctrl+A or Cmd+A)
     - Copy the entire XML (Ctrl+C or Cmd+C)
     - Paste into the parameter field in the AWS Console
     - ⚠️ **Important**: Make sure to include the `<?xml version="1.0"?>` header and all content

     **Method 2: Use a Single-Line Format**
     - If copy-paste has issues, you can minify the XML first:
     ```bash
     # Remove newlines and extra spaces
     cat britive-saml-metadata.xml | tr -d '\n' | tr -s ' '
     ```
     - Copy the output and paste into the Console

   - **Enable AWS Invalidation Feature**: Select `true` or `false` (default: `true`)
4. Click **Next**

### Step 4: Configure StackSet Options

1. **Permissions**:
   - **Permissions model**: Select **Service-managed permissions** (recommended)
   - This allows AWS to automatically create the necessary roles

2. **Execution configuration**:
   - **Active**: Keep this enabled
   - **Managed execution**: Enable for automatic rollback on failures (recommended)

3. **Tags** (Optional):
   - Add tags to help organize your StackSets
   - Example: Key=`Project`, Value=`BritiveIntegration`

4. Click **Next**

### Step 5: Set Deployment Targets

Choose one of the following deployment options:

#### Option A: Deploy to Organizational Units (Recommended)

1. **Deployment targets**: Select **Deploy to organizational units (OUs)**
2. **AWS OU IDs**:
   - Click **Add OUs**
   - Select one or more OUs from the list
   - Or manually enter OU IDs (format: `ou-xxxx-xxxxxxxx`)

   **To find your OU IDs:**
   - Go to **AWS Organizations** console
   - Navigate to **AWS accounts**
   - View the organizational structure and copy the OU IDs

3. **Automatic deployment options**:
   - ✅ **Enable automatic deployment** (recommended for new accounts)
   - **Account removal behavior**: Select **Delete stacks** (removes Britive resources when accounts leave the OU)

#### Option B: Deploy to Specific Accounts

1. **Deployment targets**: Select **Deploy to accounts**
2. **Account numbers**: Enter AWS account IDs, one per line

   **To find account IDs:**
   - Go to **AWS Organizations** console
   - Navigate to **AWS accounts** to view all account IDs

### Step 6: Specify Regions

1. **Regions**: Select **us-east-1** (or your preferred region)
   - Note: IAM resources are global, but StackSets require at least one region

2. **Deployment options**:
   - **Maximum concurrent accounts**: Choose how many accounts to deploy to simultaneously
     - Percentage: `100` (deploy to all at once)
     - Or Number: Specify a count
   - **Failure tolerance**: Specify how many failures before stopping
     - Percentage: `0` (stop on first failure)
     - Or Number: Specify a count
   - **Region Concurrency**: Select **Sequential** or **Parallel**

3. Click **Next**

### Step 7: Review and Create

1. Review all your settings
2. **Capabilities**:
   - ✅ Check **I acknowledge that AWS CloudFormation might create IAM resources with custom names**
3. Click **Submit**

### Step 8: Monitor Deployment

1. You'll be taken to the StackSet details page
2. Click the **Stack instances** tab to monitor deployment progress
3. Watch the **Status** column for each account:
   - `CURRENT`: Successfully deployed
   - `OUTDATED`: Needs update
   - `FAILED`: Deployment failed (click to see error details)
4. Click **Operations** tab to see deployment history

---

## Deployment via AWS CLI

### Prerequisites for CLI Deployment

1. Install and configure AWS CLI v2:
```bash
aws --version  # Should be 2.x or higher
aws configure  # Set up your credentials
```

2. Verify you're using the management account:
```bash
aws sts get-caller-identity
```

### Step 1: Prepare Your Parameters

#### Method 1: Using a Parameters JSON File (Recommended)

Create a parameters file to avoid putting sensitive data in command history. First, prepare your SAML metadata:

**Option A: Inline the SAML XML in JSON (Simple but requires escaping)**

```bash
# Read and escape SAML metadata for JSON
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
    "ParameterValue": $(echo $SAML_CONTENT)
  },
  {
    "ParameterKey": "DeployAwsInvalidationFeature",
    "ParameterValue": "true"
  }
]
EOF
```

**Option B: Create a helper script (Easiest)**

Save this as `generate-parameters.sh`:

```bash
#!/bin/bash

# Usage: ./generate-parameters.sh <tenant-name> <saml-metadata-file> [true|false]

TENANT_NAME=${1}
SAML_FILE=${2}
ENABLE_INVALIDATION=${3:-true}

if [ -z "$TENANT_NAME" ] || [ -z "$SAML_FILE" ]; then
  echo "Usage: $0 <tenant-name> <saml-metadata-file> [enable-invalidation]"
  echo "Example: $0 mycompany britive-saml-metadata.xml true"
  exit 1
fi

if [ ! -f "$SAML_FILE" ]; then
  echo "Error: SAML metadata file not found: $SAML_FILE"
  exit 1
fi

# Read and properly escape SAML content for JSON
SAML_CONTENT=$(cat "$SAML_FILE" | jq -Rs .)

# Generate parameters.json
cat > parameters.json << EOF
[
  {
    "ParameterKey": "TenantName",
    "ParameterValue": "${TENANT_NAME}"
  },
  {
    "ParameterKey": "SamlMetadataDocumentXmlContent",
    "ParameterValue": ${SAML_CONTENT}
  },
  {
    "ParameterKey": "DeployAwsInvalidationFeature",
    "ParameterValue": "${ENABLE_INVALIDATION}"
  }
]
EOF

echo "✓ Generated parameters.json successfully"
echo "✓ Tenant: ${TENANT_NAME}"
echo "✓ SAML file: ${SAML_FILE}"
echo "✓ Invalidation: ${ENABLE_INVALIDATION}"
```

Make it executable and run:

```bash
chmod +x generate-parameters.sh
./generate-parameters.sh mycompany britive-saml-metadata.xml true
```

#### Method 2: Using Environment Variables (Alternative)

```bash
# Load SAML metadata into variable
SAML_METADATA=$(cat britive-saml-metadata.xml)

# Use inline parameters (not recommended for production due to command history)
aws cloudformation create-stack-set \
  --stack-set-name britive-integration \
  --template-body file://britive_integration_resources_stackset.yaml \
  --parameters \
    ParameterKey=TenantName,ParameterValue=mycompany \
    ParameterKey=SamlMetadataDocumentXmlContent,ParameterValue="$SAML_METADATA" \
    ParameterKey=DeployAwsInvalidationFeature,ParameterValue=true \
  --permission-model SERVICE_MANAGED \
  --capabilities CAPABILITY_NAMED_IAM
```

#### Method 3: Using AWS Systems Manager Parameter Store (Most Secure)

Store SAML metadata securely in Parameter Store:

```bash
# Store SAML metadata
aws ssm put-parameter \
  --name "/britive/saml-metadata" \
  --value file://britive-saml-metadata.xml \
  --type "String" \
  --description "Britive SAML metadata for AWS integration"

# Retrieve and use in deployment
SAML_METADATA=$(aws ssm get-parameter \
  --name "/britive/saml-metadata" \
  --query 'Parameter.Value' \
  --output text)

# Create parameters file
cat > parameters.json << EOF
[
  {
    "ParameterKey": "TenantName",
    "ParameterValue": "mycompany"
  },
  {
    "ParameterKey": "SamlMetadataDocumentXmlContent",
    "ParameterValue": $(echo "$SAML_METADATA" | jq -Rs .)
  },
  {
    "ParameterKey": "DeployAwsInvalidationFeature",
    "ParameterValue": "true"
  }
]
EOF
```

### Step 2: Get Required IDs

**Get your Root OU ID:**
```bash
ROOT_OU_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
echo "Root OU ID: $ROOT_OU_ID"
```

**List all Organizational Units:**
```bash
aws organizations list-organizational-units-for-parent \
  --parent-id $ROOT_OU_ID \
  --query 'OrganizationalUnits[].[Name,Id]' \
  --output table
```

**List all accounts in your organization:**
```bash
aws organizations list-accounts \
  --query 'Accounts[].[Name,Id,Status]' \
  --output table
```

### Step 3: Create the StackSet

#### Option A: Deploy to Entire Organization

```bash
# Create the StackSet
aws cloudformation create-stack-set \
  --stack-set-name britive-integration \
  --template-body file://britive_integration_resources_stackset.yaml \
  --parameters file://parameters.json \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --capabilities CAPABILITY_NAMED_IAM \
  --description "Britive integration resources for AWS organization" \
  --call-as SELF

# Deploy to all accounts in the organization
aws cloudformation create-stack-instances \
  --stack-set-name britive-integration \
  --deployment-targets OrganizationalUnitIds=$ROOT_OU_ID \
  --regions us-east-1 \
  --operation-preferences \
    FailureTolerancePercentage=0,\
    MaxConcurrentPercentage=100,\
    RegionConcurrencyType=PARALLEL \
  --call-as SELF
```

#### Option B: Deploy to Specific OUs

```bash
# Set your target OU IDs
OU_ID_1="ou-xxxx-xxxxxxxx"
OU_ID_2="ou-yyyy-yyyyyyyy"

# Create the StackSet
aws cloudformation create-stack-set \
  --stack-set-name britive-integration \
  --template-body file://britive_integration_resources_stackset.yaml \
  --parameters file://parameters.json \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --capabilities CAPABILITY_NAMED_IAM \
  --description "Britive integration resources for specific OUs" \
  --call-as SELF

# Deploy to specific OUs
aws cloudformation create-stack-instances \
  --stack-set-name britive-integration \
  --deployment-targets OrganizationalUnitIds=$OU_ID_1,$OU_ID_2 \
  --regions us-east-1 \
  --operation-preferences \
    FailureTolerancePercentage=10,\
    MaxConcurrentPercentage=50,\
    RegionConcurrencyType=PARALLEL \
  --call-as SELF
```

#### Option C: Deploy to Specific Accounts

```bash
# Set your target account IDs
ACCOUNT_ID_1="123456789012"
ACCOUNT_ID_2="234567890123"
ACCOUNT_ID_3="345678901234"

# Create the StackSet
aws cloudformation create-stack-set \
  --stack-set-name britive-integration \
  --template-body file://britive_integration_resources_stackset.yaml \
  --parameters file://parameters.json \
  --permission-model SERVICE_MANAGED \
  --capabilities CAPABILITY_NAMED_IAM \
  --description "Britive integration resources for specific accounts" \
  --call-as SELF

# Deploy to specific accounts
aws cloudformation create-stack-instances \
  --stack-set-name britive-integration \
  --deployment-targets Accounts=$ACCOUNT_ID_1,$ACCOUNT_ID_2,$ACCOUNT_ID_3 \
  --regions us-east-1 \
  --operation-preferences \
    FailureTolerancePercentage=0,\
    MaxConcurrentPercentage=100,\
    RegionConcurrencyType=PARALLEL \
  --call-as SELF
```

### Step 4: Verify Deployment

```bash
# Check StackSet status
aws cloudformation describe-stack-set \
  --stack-set-name britive-integration \
  --query 'StackSet.[StackSetName,Status,Description]' \
  --output table

# List all stack instances
aws cloudformation list-stack-instances \
  --stack-set-name britive-integration \
  --query 'Summaries[].[Account,Region,Status]' \
  --output table

# Get detailed status for a specific account
aws cloudformation describe-stack-instance \
  --stack-set-name britive-integration \
  --stack-instance-account 123456789012 \
  --stack-instance-region us-east-1
```

### Deployment Options Explained

| Parameter | Description | Values |
|-----------|-------------|--------|
| `--permission-model` | How StackSets gets permissions | `SERVICE_MANAGED` (recommended) or `SELF_MANAGED` |
| `--auto-deployment` | Auto-deploy to new accounts | `Enabled=true` (recommended for OUs) |
| `RetainStacksOnAccountRemoval` | Keep stacks when account leaves OU | `true` or `false` |
| `FailureTolerancePercentage` | % of failures before stopping | `0` = stop on first failure |
| `MaxConcurrentPercentage` | % of accounts to deploy simultaneously | `100` = all at once |
| `RegionConcurrencyType` | Deploy regions sequentially or parallel | `SEQUENTIAL` or `PARALLEL` |

---

## Monitoring and Management

### Via AWS Console

1. Go to **CloudFormation** → **StackSets**
2. Click on your StackSet name
3. View tabs:
   - **Stack instances**: See deployment status per account/region
   - **Operations**: View deployment history
   - **Parameters**: See current parameter values
   - **Template**: View the template content

### Via AWS CLI

**Check StackSet status:**
```bash
aws cloudformation describe-stack-set \
  --stack-set-name britive-integration
```

**List all stack instances:**
```bash
aws cloudformation list-stack-instances \
  --stack-set-name britive-integration
```

**View specific stack instance details:**
```bash
aws cloudformation describe-stack-instance \
  --stack-set-name britive-integration \
  --stack-instance-account 123456789012 \
  --stack-instance-region us-east-1
```

**List recent operations:**
```bash
aws cloudformation list-stack-set-operations \
  --stack-set-name britive-integration \
  --max-results 10
```

**View operation details:**
```bash
aws cloudformation describe-stack-set-operation \
  --stack-set-name britive-integration \
  --operation-id <operation-id>
```

---

## Updating StackSets

### When to Update
- Changing SAML metadata (e.g., certificate rotation)
- Enabling/disabling AWS invalidation feature
- Modifying the template itself

### Via AWS Console

1. Go to **CloudFormation** → **StackSets**
2. Select your StackSet
3. Click **Actions** → **Edit StackSet details**
4. Update template or parameters as needed
5. Click through to **Set deployment options**
6. Choose deployment targets (accounts/OUs to update)
7. Click **Next** and **Submit**

### Via AWS CLI

**Update StackSet with new parameters:**
```bash
aws cloudformation update-stack-set \
  --stack-set-name britive-integration \
  --template-body file://britive_integration_resources_stackset.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --operation-preferences \
    FailureTolerancePercentage=10,\
    MaxConcurrentPercentage=50
```

**Update only specific stack instances:**
```bash
aws cloudformation update-stack-instances \
  --stack-set-name britive-integration \
  --deployment-targets Accounts=123456789012,234567890123 \
  --regions us-east-1 \
  --operation-preferences \
    FailureTolerancePercentage=0,\
    MaxConcurrentPercentage=100
```

---

## Deleting StackSets

### Via AWS Console

1. Go to **CloudFormation** → **StackSets**
2. Select your StackSet
3. First, delete all stack instances:
   - Click **Actions** → **Delete stacks from StackSet**
   - Choose **Delete all stacks**
   - Confirm deletion
4. Once all instances are deleted:
   - Click **Actions** → **Delete StackSet**
   - Confirm deletion

### Via AWS CLI

**Step 1: Delete all stack instances**

For OU-based deployments:
```bash
aws cloudformation delete-stack-instances \
  --stack-set-name britive-integration \
  --deployment-targets OrganizationalUnitIds=$ROOT_OU_ID \
  --regions us-east-1 \
  --no-retain-stacks \
  --call-as SELF
```

For account-based deployments:
```bash
aws cloudformation delete-stack-instances \
  --stack-set-name britive-integration \
  --deployment-targets Accounts=123456789012,234567890123 \
  --regions us-east-1 \
  --no-retain-stacks \
  --call-as SELF
```

**Step 2: Wait for instances to be deleted**
```bash
# Monitor deletion progress
aws cloudformation list-stack-instances \
  --stack-set-name britive-integration \
  --query 'Summaries[].[Account,Region,Status]' \
  --output table
```

**Step 3: Delete the StackSet**
```bash
aws cloudformation delete-stack-set \
  --stack-set-name britive-integration \
  --call-as SELF
```

---

## Auto-Deployment for New Accounts

When you enable auto-deployment, StackSets automatically deploy to:
- **New accounts** created in the organization
- **Accounts moved** into the targeted OUs
- Ensures consistent Britive integration across all accounts without manual intervention

### Verify Auto-Deployment is Enabled

**Via Console:**
1. Go to StackSet details
2. Check **Auto-deployment** status in the overview

**Via CLI:**
```bash
aws cloudformation describe-stack-set \
  --stack-set-name britive-integration \
  --query 'StackSet.AutoDeployment'
```

---

## Parameters Reference

| Parameter | Description | Example | Required |
|-----------|-------------|---------|----------|
| `TenantName` | Britive tenant name (without .britive-app.com) | `mycompany` | Yes |
| `SamlMetadataDocumentXmlContent` | Full XML content from SAML metadata file | `<?xml version="1.0"?>...` | Yes |
| `DeployAwsInvalidationFeature` | Enable additional IAM permissions for AWS invalidation | `true` or `false` | No (default: `true`) |

---

## Comparison: Single Account vs StackSet

| Feature | Single Account Stack | StackSet |
|---------|---------------------|----------|
| **Deployment Scope** | One account at a time | Multiple accounts simultaneously |
| **Management** | Individual stack per account | Centralized management |
| **Updates** | Update each stack individually | Single update applies to all |
| **New Accounts** | Manual deployment required | Automatic with auto-deployment |
| **Best For** | Testing, POC, single account | Production, organization-wide |
| **Complexity** | Simple | Moderate |

---

## Best Practices

1. **Start Small**: Test with a dev/test OU or single account before organization-wide deployment
2. **Enable Auto-Deployment**: Ensures new accounts automatically receive Britive integration
3. **Use Service-Managed Permissions**: Easier than self-managed and recommended by AWS
4. **Monitor Operations**: Always check operation status after deployment/updates
5. **Version Control**: Keep templates in Git and track parameter changes
6. **Tag Resources**: Use consistent tagging for cost allocation and organization
7. **Document Parameters**: Maintain secure documentation of parameter values (especially SAML metadata location)
8. **Test Updates**: Test StackSet updates in non-production OUs first
9. **Set Failure Tolerance**: Use appropriate failure tolerance for large deployments

---

## Troubleshooting

### Stack Instance Failed

**Via Console:**
1. Go to **StackSets** → Select your StackSet → **Stack instances** tab
2. Find failed instances (Status: `FAILED`)
3. Click on the account ID to view error details
4. Check **Events** tab for specific error messages

**Via CLI:**
```bash
# Find failed instances
aws cloudformation list-stack-instances \
  --stack-set-name britive-integration \
  --query 'Summaries[?Status==`FAILED`].[Account,Region,StatusReason]' \
  --output table

# Get detailed error for specific account
aws cloudformation describe-stack-instance \
  --stack-set-name britive-integration \
  --stack-instance-account 123456789012 \
  --stack-instance-region us-east-1 \
  --query 'StackInstance.StatusReason'
```

**Common Causes:**
- Resource already exists (e.g., role name conflict)
- Insufficient permissions in target account
- Service limits reached (e.g., IAM role limit)

### Permission Issues

**Symptoms:**
- Error: "User is not authorized to perform cloudformation:CreateStackSet"
- StackSet creation fails

**Solutions:**
1. Ensure you're in the management account or delegated administrator
2. Verify trusted access is enabled:
   ```bash
   aws organizations list-aws-service-access-for-organization \
     --query 'EnabledServicePrincipals[?ServicePrincipal==`member.org.stacksets.cloudformation.amazonaws.com`]'
   ```
3. Enable trusted access if not enabled:
   ```bash
   aws organizations enable-aws-service-access \
     --service-principal member.org.stacksets.cloudformation.amazonaws.com
   ```

### Resource Already Exists

**Error:** "Resource already exists: britive-mycompany-integration-role"

**Solutions:**

**Option 1: Delete existing resources**
- Manually delete the conflicting resources in the target account(s)
- Re-run the StackSet deployment

**Option 2: Skip accounts with existing resources**
- Deploy to accounts without conflicts first
- Handle conflicting accounts separately

**Option 3: Import existing resources (Advanced)**
- Use CloudFormation import to bring existing resources under StackSet management

### SAML Metadata Issues

**Error:** "Invalid SAML metadata document"

**Solutions:**
1. Verify XML is well-formed (no extra spaces, newlines)
2. Ensure entire XML content is copied including `<?xml version="1.0"?>` header
3. Check for special characters that need escaping in JSON format
4. Download fresh SAML metadata from Britive

**Test SAML metadata:**
```bash
# Validate XML structure
xmllint --noout saml-metadata.xml && echo "Valid XML" || echo "Invalid XML"
```

### Deployment Timeout

**Symptoms:**
- Operations taking longer than expected
- Some instances stuck in `RUNNING` state

**Solutions:**
1. Check AWS Service Health Dashboard for CloudFormation issues
2. Reduce `MaxConcurrentPercentage` to deploy more slowly
3. Increase `FailureTolerancePercentage` to continue despite some failures
4. Check individual account CloudFormation stacks for specific errors

### Auto-Deployment Not Working

**Symptoms:**
- New accounts not automatically getting stacks

**Verify:**
```bash
# Check auto-deployment configuration
aws cloudformation describe-stack-set \
  --stack-set-name britive-integration \
  --query 'StackSet.AutoDeployment'
```

**Solutions:**
1. Ensure auto-deployment is enabled and targeting the correct OUs
2. Verify new accounts are in the targeted OUs
3. Check that trusted access is enabled for CloudFormation StackSets

---

## Getting Help

### AWS Resources
- **CloudFormation StackSets Documentation**: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html
- **AWS Organizations Documentation**: https://docs.aws.amazon.com/organizations/
- **AWS Support**: Open a support case in the AWS Console

### Britive Resources
- **Britive Documentation**: Contact your Britive account team
- **SAML Configuration**: Consult Britive AWS integration guides

### Common AWS CLI Commands Reference

```bash
# List all StackSets
aws cloudformation list-stack-sets

# Get StackSet details
aws cloudformation describe-stack-set --stack-set-name britive-integration

# List stack instances
aws cloudformation list-stack-instances --stack-set-name britive-integration

# List operations
aws cloudformation list-stack-set-operations --stack-set-name britive-integration

# Stop a running operation
aws cloudformation stop-stack-set-operation \
  --stack-set-name britive-integration \
  --operation-id <operation-id>

# Get operation results
aws cloudformation list-stack-set-operation-results \
  --stack-set-name britive-integration \
  --operation-id <operation-id>
```

---

## Additional Notes

### IAM Resources are Global
While you must specify a region for StackSet deployment (e.g., `us-east-1`), the IAM resources created (SAML providers, roles) are global and accessible from all regions.

### Cost Considerations
- StackSets themselves have no additional cost
- You pay for the CloudFormation stacks created in each account (no charge for IAM resources)
- No ongoing costs for IAM roles and SAML providers

### Compliance and Security
- All IAM resources are created with least-privilege access
- SAML provider uses federated authentication
- Integration role has read-only access to IAM and Organizations
- AWS Invalidation feature adds write permissions only to `britive/managed/*` policy namespace

### Multi-Region Considerations
If you need to deploy to multiple regions (though not typical for IAM resources):
```bash
aws cloudformation create-stack-instances \
  --stack-set-name britive-integration \
  --deployment-targets OrganizationalUnitIds=$OU_ID \
  --regions us-east-1 us-west-2 eu-west-1
```
