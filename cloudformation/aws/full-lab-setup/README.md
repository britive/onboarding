# Britive AWS CloudFormation Stack

This CloudFormation template sets up a complete AWS environment integrated with Britive, including:
- VPC with 2 public subnets
- Amazon RDS MySQL with credentials stored in Secrets Manager (encrypted using a KMS key)
- EC2 Instances (Amazon Linux and Windows) with a generated EC2 Key Pair
- IAM Roles for EC2, RDS, and Admin access, with Britive SAML-based federated access
- Secrets and IAM policy for Britive AWS Invalidation feature (optional)

## 🔧 Parameters

### Prepare Parameters

1. Tenant name is the prefix part of your tenant URL.
2. AWS Invalidation function is optional but recommended for all AWS Integrations
3. SamlMetadata for your Tenant is available under System Admin > Security > SAML Configurations.
   Download the metadata xml file and transform it as follows for processing with cloudformation.
   ```bash
   tr '\n' ' ' < metadata.xml | sed 's/>[ \t]*</></g' | sed 's/<\/root><root>/<\/root>\n<root>/g' | sed 's/"/\\"/g'
   ```
   Copy the output of the above command as the "SamlMetadataDocumentXmlContent" in the parameters.json file.

| Parameter                         | Description                                                                                |
|-----------------------------------|--------------------------------------------------------------------------------------------|
| `TenantName`                      | Name of your Britive tenant (e.g. `example` if URL is `example.britive-app.com`)           |
| `SamlMetadataDocumentXmlContent`  | Contents of the SAML metadata XML downloaded from Britive after above formatting changes   |
| `DeployAwsInvalidationFeature`    | Set to `true` to enable extra IAM permissions for AWS Invalidation                         |


## 🚀 How to Deploy

### Command-line interface

Run the following command to create the stack.
```bash
aws cloudformation create-stack \
  --stack-name britive-lab-resources \
  --template-body file://britive_lab_resources.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

### AWS Console

1. Open the AWS CloudFormation Console.
2. Click **"Create stack"** > **"With new resources (standard)"**.
3. Upload the `britive_lab_resources.yaml` template file.
4. Provide required parameters:
   - Britive tenant name
   - SAML metadata XML content
   - Whether to enable the AWS invalidation feature
5. Acknowledge IAM resource creation and create the stack.

## 🔐 Notes

- An EC2 Key Pair is created automatically in AWS. You can retrieve the public key from EC2 > Key Pairs.
- The RDS credentials are generated and stored securely in AWS Secrets Manager under `BritiveRdsAdminSecret`.
- A new KMS key is created to encrypt the secret.
- EC2 Security Group allows SSH (port 22), RDP (port 3389), and MySQL (port 3306) from 0.0.0.0/0. Modify this for production.

## 📎 Outputs & Resources Created

- IAM SAML Provider and Integration Role
- EC2 and RDS IAM Roles with optional invalidation support
- Key Pair for EC2
- KMS key and Secret for RDS credentials
- Linux and Windows EC2 Instances
- RDS MySQL Instance

---

🛡️ Please audit IAM and network permissions before production use.
