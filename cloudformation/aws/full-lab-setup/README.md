# Lab: integration, sample roles and targets

[`britive_lab_resources.yaml`](britive_lab_resources.yaml) builds a complete
environment to demonstrate Britive on AWS: the integration, four sample JIT
roles, and targets to use them against — an Amazon Linux 2023 instance, a
Windows Server 2022 instance and a MySQL database in their own VPC.
Terraform equivalent: [`../../../terraform/aws/full-lab-setup/`](../../../terraform/aws/full-lab-setup/).

**For demonstrations and proofs of concept only.** It creates billable
resources (two instances, an RDS instance; roughly USD 50 per month) and
exposes them to the one CIDR you allow. Delete the stack when the demo is
over.

## What it creates

| Area | Resources |
| ---- | --------- |
| Britive | SAML provider `britive-<tenant>`, integration role `britive-<tenant>-integration-role`, optional invalidation permissions |
| Sample JIT roles | `Readonly-admin-role`, `Poweruser-role`, `EC2-Fullaccess-role`, `S3-Fullaccess-role` |
| Network | VPC `10.0.0.0/16`, two public subnets, internet gateway, security group open to `AllowedIngressCidr` only (`0.0.0.0/0` is rejected by a template rule) |
| Compute | Amazon Linux 2023 `t3.micro`, Windows Server 2022 `t3.small`, IMDSv2, encrypted disks, one ED25519 key pair whose private key EC2 stores in Parameter Store |
| Database | MySQL `db.t3.micro`, encrypted with a KMS key, credentials in Secrets Manager, deleted with the stack (no final snapshot) |

## Deploy

Download the SAML metadata (**System Administration → Security → SAML
Configurations → Download SAML Metadata**), find your public IP
(`curl -s https://checkip.amazonaws.com`), then:

```bash
cd .. && ./generate-parameters.sh acme britive-saml-metadata.xml -o /tmp/base.json && cd -
cp parameters.example.json parameters.json
# copy SamlMetadataDocumentXmlContent from /tmp/base.json; set TenantName and AllowedIngressCidr

aws cloudformation deploy \
  --stack-name britive-lab \
  --template-file britive_lab_resources.yaml \
  --parameter-overrides file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
# 10-15 minutes, mostly RDS

aws cloudformation describe-stacks --stack-name britive-lab --query 'Stacks[0].Outputs' --output table
```

Console: **CloudFormation → Create stack → Upload a template file** →
`britive_lab_resources.yaml`; paste the metadata XML and your `/32`.

## Configure Britive

**System Administration → Tenant Applications → Create Application → AWS
Standalone**: `AccountId`, `BritiveSamlProviderName`,
`BritiveIntegrationRoleName`, `BackendConnectionDurationHours` (1) from the
outputs, then **Save and Test**. Create a profile per sample role and check
one out: the console session lands in this account with that role.

## Reach the targets

```bash
# private key: EC2 stored it in Parameter Store under the key pair id
KEY_ID=$(aws cloudformation describe-stacks --stack-name britive-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`KeyPairId`].OutputValue' --output text)
aws ssm get-parameter --name "/ec2/keypair/$KEY_ID" --with-decryption \
  --query Parameter.Value --output text > lab-key.pem && chmod 600 lab-key.pem

LINUX_IP=$(aws cloudformation describe-stacks --stack-name britive-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`LinuxInstancePublicIp`].OutputValue' --output text)
ssh -i lab-key.pem ec2-user@"$LINUX_IP"

WIN_ID=$(aws cloudformation describe-stacks --stack-name britive-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`WindowsInstanceId`].OutputValue' --output text)
aws ec2 get-password-data --instance-id "$WIN_ID" --priv-launch-key lab-key.pem \
  --query PasswordData --output text        # then RDP to WindowsInstancePublicIp as Administrator

SECRET=$(aws cloudformation describe-stacks --stack-name britive-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`RdsSecretArn`].OutputValue' --output text)
aws secretsmanager get-secret-value --secret-id "$SECRET" --query SecretString --output text
RDS=$(aws cloudformation describe-stacks --stack-name britive-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`RdsEndpoint`].OutputValue' --output text)
mysql -h "$RDS" -u britive -p
```

## Parameters

| Parameter | Default | Description |
| --------- | ------- | ----------- |
| `TenantName` | — | Tenant subdomain |
| `SamlMetadataDocumentXmlContent` | — | SAML metadata XML (contents) |
| `DeployAwsInvalidationFeature` | `true` | Session-invalidation permissions |
| `AllowedIngressCidr` | — | The only CIDR that can reach the lab; `0.0.0.0/0` is rejected |

## Teardown

```bash
aws cloudformation delete-stack --stack-name britive-lab
aws cloudformation wait stack-delete-complete --stack-name britive-lab
rm -f lab-key.pem
```

Everything is removed, including the database (no snapshot) and the secret.
The KMS key is scheduled for deletion (7 days). Remove the application from
Britive as well.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Stack rejected: `AllowedIngressCidr must not be 0.0.0.0/0` | The template rule | Use your public IP as a `/32` |
| `DBSubnetGroupDoesNotCoverEnoughAZs` | Region with one usable AZ | Deploy in a region with at least two |
| Cannot SSH / RDP | Your IP changed, or the key was not fetched | Update `AllowedIngressCidr`; fetch the key from Parameter Store as above |
| `Role … already exists` | A previous lab or the single-account stack is in this account | One Britive integration per account; delete the other stack first |
