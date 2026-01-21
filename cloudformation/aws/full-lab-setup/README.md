# Britive Full Lab Setup - Complete Demo Environment

This CloudFormation template creates a complete AWS demo environment with Britive integration, perfect for training, demonstrations, and testing Britive's privileged access management capabilities.

## Overview

This all-in-one template deploys:

- **Networking**: VPC with 2 public subnets across availability zones
- **Compute**: Amazon Linux and Windows EC2 instances with auto-generated key pairs
- **Database**: Amazon RDS MySQL with encrypted credentials in Secrets Manager
- **Security**: IAM roles for EC2, RDS, and admin access with Britive SAML federation
- **Britive Integration**: SAML provider, integration role, and optional AWS invalidation feature

## When to Use This Template

Use this full lab setup when:

- Creating a **demo environment** to showcase Britive capabilities
- Setting up a **training environment** for users to learn Britive
- Building a **sandbox environment** for testing access policies
- Evaluating Britive with **realistic AWS resources**

**Not recommended for:**

- Production environments (security groups are intentionally permissive)
- Single integration role deployment only (use [Single Account Stack](../single-account-stack/) instead)
- Organization-wide deployments (use [StackSet Templates](../stackset-templates/) instead)

## What Gets Deployed

### Networking Resources

- **VPC**: 10.0.0.0/16 CIDR block
- **Public Subnets**: 2 subnets in different availability zones
  - Subnet 1: 10.0.1.0/24
  - Subnet 2: 10.0.2.0/24
- **Internet Gateway**: For public internet access
- **Route Table**: Routes internet traffic through IGW
- **Security Group**: Allows SSH (22), RDP (3389), and MySQL (3306) from 0.0.0.0/0

### Compute Resources

- **Amazon Linux EC2 Instance**: t2.micro in first public subnet
- **Windows EC2 Instance**: t3.small in first public subnet
- **EC2 Key Pair**: Auto-generated for SSH/RDP access
- **EC2 IAM Role**: Role for EC2 instances with Britive SAML trust

### Database Resources

- **RDS MySQL Instance**: db.t3.micro in public subnet
  - Engine: MySQL 8.0
  - Storage: 20 GB gp2
  - Publicly accessible for demo purposes
- **RDS Credentials Secret**: Stored in AWS Secrets Manager
  - Username: admin
  - Password: Auto-generated
- **KMS Key**: Customer-managed key for encrypting the secret
- **RDS IAM Role**: Role for database access with Britive SAML trust

### Britive Integration Resources

- **SAML Identity Provider**: `britive-<tenant-name>`
- **Integration Role**: `britive-<tenant-name>-integration-role`
  - Permissions: IAMReadOnlyAccess, AWSOrganizationsReadOnlyAccess
  - Optional: AWS Invalidation feature
- **Admin Role**: Role with broader permissions for testing
- **JIT Roles**: Sample roles that can be checked out via Britive

## Prerequisites

Before deploying, ensure you have:

1. **Britive Tenant**: Active Britive account (e.g., `mycompany.britive-app.com`)
2. **SAML Metadata**: Downloaded from Britive
   - Navigate to: Settings → Identity Providers → AWS → Download SAML Metadata
3. **AWS Permissions**: Ability to create VPC, EC2, RDS, IAM, KMS, and Secrets Manager resources
4. **AWS CLI** (optional): For command-line deployment

## Parameters

| Parameter | Description | Example | Required |
|-----------|-------------|---------|----------|
| `TenantName` | Britive tenant name (without .britive-app.com) | `mycompany` | Yes |
| `SamlMetadataDocumentXmlContent` | Full SAML metadata XML content | `<?xml version="1.0"?>...` | Yes |
| `DeployAwsInvalidationFeature` | Enable AWS invalidation permissions | `true` or `false` | No (default: `true`) |

### Preparing SAML Metadata

The SAML metadata must be properly formatted for CloudFormation. You can use one of these methods:

#### Method 1: Using the Helper Script (Recommended)

Use the helper script from the stackset-templates directory:

```bash
cd /path/to/cloudformation/aws

# Generate parameters.json with properly escaped SAML metadata
./stackset-templates/generate-parameters.sh mycompany metadata.xml true

# The script creates parameters.json ready to use
```

#### Method 2: Manual Formatting

If you need to format manually:

```bash
# Download metadata from Britive, then format it
tr '\n' ' ' < metadata.xml | sed 's/>[ \t]*</></g' | sed 's/<\/root><root>/<\/root>\n<root>/g' | sed 's/"/\\"/g'
```

Copy the output as the `SamlMetadataDocumentXmlContent` value in parameters.json.

## Deployment

### Via AWS CLI

```bash
# Create the stack
aws cloudformation create-stack \
  --stack-name britive-lab-resources \
  --template-body file://britive_lab_resources.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Monitor deployment (takes 10-15 minutes)
aws cloudformation wait stack-create-complete \
  --stack-name britive-lab-resources \
  --region us-east-1

# Get stack outputs
aws cloudformation describe-stacks \
  --stack-name britive-lab-resources \
  --region us-east-1 \
  --query 'Stacks[0].Outputs' \
  --output table
```

### Via AWS Console

1. Navigate to **CloudFormation** in the AWS Management Console
2. Click **Create stack** → **With new resources (standard)**
3. **Upload template**: Select `britive_lab_resources.yaml`
4. **Stack name**: Enter `britive-lab-resources`
5. **Parameters**:
   - Enter your Britive tenant name
   - Paste the full SAML metadata XML content
   - Choose whether to enable AWS invalidation feature
6. **Configure stack options**: Add tags if desired
7. **Review**: Acknowledge that CloudFormation will create IAM resources
8. Click **Create stack**
9. Monitor progress in the **Events** tab (10-15 minutes)

## Post-Deployment

### Retrieving Stack Outputs

After successful deployment, get important information from stack outputs:

```bash
aws cloudformation describe-stacks \
  --stack-name britive-lab-resources \
  --region us-east-1 \
  --query 'Stacks[0].Outputs'
```

### Accessing EC2 Instances

#### Retrieve EC2 Key Pair

The key pair is auto-generated. Retrieve the public key:

```bash
# Get key pair name from outputs
KEY_PAIR_NAME=$(aws cloudformation describe-stacks \
  --stack-name britive-lab-resources \
  --query 'Stacks[0].Outputs[?OutputKey==`EC2KeyPairName`].OutputValue' \
  --output text)

# View public key
aws ec2 describe-key-pairs \
  --key-names $KEY_PAIR_NAME \
  --query 'KeyPairs[0].PublicKey' \
  --output text
```

**Note**: The private key is **not stored** by AWS. For demo purposes, you may need to create a new key pair and associate it with the instances.

#### Get Instance IPs

```bash
# Get instance IDs from stack resources
aws cloudformation describe-stack-resources \
  --stack-name britive-lab-resources \
  --query 'StackResources[?ResourceType==`AWS::EC2::Instance`].[LogicalResourceId,PhysicalResourceId]' \
  --output table

# Get public IPs
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].PublicIpAddress'
```

### Accessing RDS Database

Retrieve RDS credentials from Secrets Manager:

```bash
# Get secret ARN from stack outputs
SECRET_ARN=$(aws cloudformation describe-stacks \
  --stack-name britive-lab-resources \
  --query 'Stacks[0].Outputs[?OutputKey==`RDSSecretArn`].OutputValue' \
  --output text)

# Retrieve credentials
aws secretsmanager get-secret-value \
  --secret-id $SECRET_ARN \
  --query 'SecretString' \
  --output text | jq .

# Get RDS endpoint
RDS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name britive-lab-resources \
  --query 'Stacks[0].Outputs[?OutputKey==`RDSEndpoint`].OutputValue' \
  --output text)

echo "RDS Endpoint: $RDS_ENDPOINT"
```

Connect to MySQL:

```bash
# Get username and password from secret
USERNAME=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query 'SecretString' --output text | jq -r .username)
PASSWORD=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query 'SecretString' --output text | jq -r .password)

# Connect
mysql -h $RDS_ENDPOINT -u $USERNAME -p$PASSWORD
```

### Configuring Britive

1. **Add AWS Account**:
   - Log into Britive tenant
   - Navigate to: Applications → Add Application → AWS
   - Enter AWS account ID and region

2. **Configure Integration**:
   - Use the integration role ARN from stack outputs
   - Test the connection

3. **Create Profiles**:
   - Create profiles for the deployed IAM roles (EC2 Role, RDS Role, Admin Role)
   - Set up access policies and approval workflows

4. **Test Access**:
   - Assign users to profiles
   - Request checkout of roles
   - Verify access to EC2 instances and RDS database

## Resources Created - Complete List

### IAM Resources

- SAML Provider: `britive-<tenant>`
- Integration Role: `britive-<tenant>-integration-role`
- EC2 Role: `Britive-EC2-Role`
- RDS Role: `Britive-RDS-Role`
- Admin Role: `Britive-Admin-Role`

### Network Resources

- VPC
- Internet Gateway
- 2 Public Subnets
- Route Table with IGW route
- Security Group (allows 22, 3389, 3306 from 0.0.0.0/0)

### Compute Resources

- EC2 Instance (Amazon Linux)
- EC2 Instance (Windows)
- EC2 Key Pair

### Database Resources

- RDS MySQL Instance
- RDS Subnet Group

### Security Resources

- KMS Key for encrypting secrets
- Secrets Manager Secret for RDS credentials

## Cost Estimate

Approximate monthly costs for running this lab (us-east-1 pricing):

| Resource | Type | Quantity | Est. Monthly Cost |
|----------|------|----------|-------------------|
| EC2 Linux | t2.micro | 1 | ~$8 |
| EC2 Windows | t3.small | 1 | ~$15 |
| RDS MySQL | db.t3.micro | 1 | ~$25 |
| RDS Storage | gp2 20GB | 1 | ~$2.50 |
| KMS Key | Customer managed | 1 | ~$1 |
| Secrets Manager | Secret | 1 | ~$0.40 |
| **Total** | - | - | **~$52/month** |

**Cost Optimization Tips**:

- Stop EC2 instances when not in use (~50% savings)
- Delete the stack when demos are complete (avoid ongoing charges)
- Use AWS Free Tier if eligible

## Security Considerations

### For Demo/Lab Use Only

This template is designed for demonstration and includes intentionally permissive settings:

- **Security Group**: Allows SSH, RDP, and MySQL from any IP (0.0.0.0/0)
- **RDS**: Publicly accessible
- **Subnets**: All resources in public subnets

### Before Production Use

**Never use this template for production.** If adapting for production:

1. **Network Security**:
   - Place RDS in private subnets
   - Restrict security group ingress to specific IP ranges
   - Use VPN or bastion hosts for access

2. **EC2 Security**:
   - Implement proper key management
   - Use AWS Systems Manager Session Manager instead of SSH
   - Enable detailed monitoring and logging

3. **Database Security**:
   - Disable public accessibility
   - Enable encryption at rest
   - Enable automated backups
   - Use SSL/TLS for connections

4. **IAM Security**:
   - Apply principle of least privilege to roles
   - Enable MFA for role assumptions
   - Review and limit permissions

5. **Monitoring**:
   - Enable CloudTrail logging
   - Set up CloudWatch alarms
   - Enable VPC Flow Logs

## Updating the Stack

To update parameters (e.g., rotate SAML certificate):

```bash
# Update parameters.json with new values

# Update the stack
aws cloudformation update-stack \
  --stack-name britive-lab-resources \
  --template-body file://britive_lab_resources.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Monitor update
aws cloudformation wait stack-update-complete \
  --stack-name britive-lab-resources \
  --region us-east-1
```

## Deleting the Lab Environment

To remove all resources and stop charges:

```bash
# Delete the stack
aws cloudformation delete-stack \
  --stack-name britive-lab-resources \
  --region us-east-1

# Monitor deletion
aws cloudformation wait stack-delete-complete \
  --stack-name britive-lab-resources \
  --region us-east-1
```

**Note**: Some resources may require manual deletion if the stack deletion fails:

- RDS instances with deletion protection enabled
- Non-empty KMS keys
- Retained secrets in Secrets Manager

## Troubleshooting

### Stack Creation Failed

Check the CloudFormation events for specific errors:

```bash
aws cloudformation describe-stack-events \
  --stack-name britive-lab-resources \
  --max-items 20
```

### Common Issues

**Issue**: "DBSubnetGroupDoesNotCoverEnoughAZs"
- **Solution**: Ensure VPC has subnets in at least 2 availability zones

**Issue**: "InvalidParameterValue: Invalid SAML metadata"
- **Solution**: Verify SAML metadata is properly formatted and complete

**Issue**: "InsufficientCapacityException" for EC2
- **Solution**: Try a different availability zone or instance type

**Issue**: Cannot connect to EC2 instances
- **Solution**: EC2 key pair private key is not stored by AWS; you may need to create and assign a new key pair

## Additional Resources

- [Britive Documentation](https://docs.britive.com)
- [AWS VPC User Guide](https://docs.aws.amazon.com/vpc/)
- [Amazon RDS User Guide](https://docs.aws.amazon.com/rds/)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
- [Single Account Stack](../single-account-stack/) - For integration-only deployment
- [StackSet Templates](../stackset-templates/) - For multi-account deployment

## Support

For assistance with:

- **CloudFormation**: AWS documentation or AWS Support
- **Britive Integration**: Britive support or your account team
- **Template Issues**: Open an issue or contact the repository maintainers

---

**Important**: This template creates billable AWS resources. Remember to delete the stack when finished with demos to avoid ongoing charges.

