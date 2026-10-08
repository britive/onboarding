# Britive AWS lab (Terraform)

A complete environment to demonstrate Britive on AWS in one `apply`: the
integration (through [`../modules/britive-integration`](../modules/britive-integration/)),
four sample JIT roles, and targets to use them against — a Linux instance, a
Windows instance and a MySQL database in their own VPC. Equivalent to
[`../../../cloudformation/aws/full-lab-setup/`](../../../cloudformation/aws/full-lab-setup/).

**For demonstrations and proofs of concept only.** It creates billable
resources (two instances, an RDS instance; roughly USD 50 per month) and
exposes them to the CIDR you allow. Destroy it when the demo is over.

## What it creates

| Area | Resources |
| ---- | --------- |
| Britive | SAML provider `britive-<tenant>`, integration role `britive-<tenant>-integration-role`, optional invalidation permissions |
| Sample JIT roles | `Readonly-admin-role`, `Poweruser-role`, `EC2-Fullaccess-role`, `S3-Fullaccess-role` |
| Network | VPC (`10.0.0.0/16`), two public subnets, internet gateway, security group open to `allowed_ingress_cidr` only |
| Compute | Amazon Linux 2023 `t3.micro` and Windows Server 2022 `t3.small`, IMDSv2, encrypted disks, one key pair (generated unless you supply a public key) |
| Database | MySQL 8.0 `db.t3.micro`, encrypted with a KMS key, credentials in Secrets Manager |

## Prerequisites

- Terraform >= 1.5 and credentials for a sandbox account
- The SAML metadata XML from your tenant: **System Administration → Security
  → SAML Configurations → Download SAML Metadata**
- Your public IP (`curl -s https://checkip.amazonaws.com`) for
  `allowed_ingress_cidr`

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars   # tenant_name, allowed_ingress_cidr
terraform init
terraform apply -var="saml_metadata_document_xml_content=$(cat britive-saml-metadata.xml)"

# Save the generated private key (skip if you supplied ssh_public_key)
terraform output -raw generated_private_key_pem > lab-key.pem && chmod 600 lab-key.pem
```

## Configure the application in Britive

**System Administration → Tenant Applications → Create Application → AWS
Standalone** (a single account), then:

| Britive field | Terraform output |
| ------------- | ---------------- |
| Account ID | `account_id` |
| Identity Provider Name | `saml_provider_name` |
| Integration Role Name | `integration_role_name` |
| Duration of backend connection (hours) | `backend_connection_duration_hours` |
| Region | `region` you deployed to |

After **Save and Test**, create a profile per sample role and check one out
from the Britive console: the console session lands in this account with
that role.

## Reach the targets

```bash
ssh -i lab-key.pem ec2-user@$(terraform output -raw linux_instance_public_ip)

aws ec2 get-password-data --instance-id $(terraform output -raw windows_instance_id) \
  --priv-launch-key lab-key.pem --query PasswordData --output text   # then RDP to windows_instance_public_ip

aws secretsmanager get-secret-value --secret-id $(terraform output -raw rds_secret_arn) \
  --query SecretString --output text
mysql -h $(terraform output -raw rds_endpoint | cut -d: -f1) -u britive -p
```

## Variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `tenant_name` | — | Tenant subdomain |
| `saml_metadata_document_xml_content` | — | SAML metadata XML (contents) |
| `allowed_ingress_cidr` | — | The only CIDR allowed to reach the lab; `0.0.0.0/0` is rejected |
| `deploy_aws_invalidation_feature` | `true` | Session-invalidation permissions |
| `ssh_public_key` | `""` | Your public key; empty generates a key pair |
| `region` | `us-east-1` | Lab region |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR |

## Teardown

```bash
terraform destroy
```

Everything is removed, including the secret (no recovery window) and the
database (no final snapshot). Remove the application from Britive and delete
`lab-key.pem` afterwards.
