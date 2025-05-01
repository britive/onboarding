*BETA*

# Britive AWS CloudFormation Stack

This CloudFormation template sets up a complete AWS environment integrated with Britive, including:
- VPC with 2 public subnets
- Amazon RDS MySQL with credentials stored in Secrets Manager (encrypted using a KMS key)
- EC2 Instances (Amazon Linux and Windows) with a generated EC2 Key Pair
- IAM Roles for EC2, RDS, and Admin access, with Britive SAML-based federated access
- Secrets and IAM policy for Britive AWS Invalidation feature (optional)

## 🔧 Parameters

| Parameter                         | Description                                                                       |
|-----------------------------------|-----------------------------------------------------------------------------------|
| `TenantName`                      | Name of your Britive tenant (e.g. `example` if URL is `example.britive-app.com`)  |
| `SamlMetadataDocumentXmlContent`  | Contents of the SAML metadata XML downloaded from Britive                         |
| `DeployAwsInvalidationFeature`    | Set to `true` to enable extra IAM permissions for AWS Invalidation                |

## 🚀 How to Deploy

1. Open the AWS CloudFormation Console.
2. Click **"Create stack"** > **"With new resources (standard)"**.
3. Upload the `britive_infra.yaml` template file.
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
