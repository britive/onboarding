# Britive AWS integration — single account (Terraform)

Creates what Britive needs in one AWS account: the SAML identity provider and
the integration role, with the optional session-invalidation, Access Builder
and AI-scanning permissions, and optionally four sample JIT roles for a
demonstration. Equivalent to the CloudFormation templates in
[`../../../cloudformation/aws/single-account-stack/`](../../../cloudformation/aws/single-account-stack/).

Use this for a standalone account, a proof of concept, or the **management
account** of an organization (service-managed StackSets cannot target it —
see [`../organization-stackset/`](../organization-stackset/) for the rest of
the organization).

## Prerequisites

- Terraform >= 1.5 and AWS credentials for the target account with
  permission to create IAM roles, policies and SAML providers
- The SAML metadata XML from your tenant: **System Administration → Security
  → SAML Configurations → Download SAML Metadata**. It identifies your
  tenant, so keep it out of version control, but it contains only the
  identity provider's public signing certificate.
- Product steps and prerequisites:
  [Britive AWS onboarding guide](https://docs.britive.com/docs/application-onboarding-guides)

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars   # set tenant_name and the flags
terraform init
terraform apply -var="saml_metadata_document_xml_content=$(cat britive-saml-metadata.xml)"
```

Set `deploy_sample_roles = true` for the four demonstration roles
(`Readonly-admin-role`, `Poweruser-role`, `EC2-Fullaccess-role`,
`S3-Fullaccess-role`). They are plain IAM roles trusting the Britive SAML
provider; delete them, or set the flag back to `false`, before production use.

## Configure the application in Britive

**System Administration → Tenant Applications → Create Application → AWS**
(or **AWS Standalone** for an account outside an organization), then map the
outputs:

| Britive field | Terraform output |
| ------------- | ---------------- |
| Management Account ID / Account ID | `account_id` |
| Identity Provider Name | `saml_provider_name` |
| Integration Role Name | `integration_role_name` (the name, not the ARN) |
| Duration of backend connection (hours) | `backend_connection_duration_hours` |
| Region | the region you deploy workloads in |

**Save and Test** runs the first scan. The sample roles (if created) then
appear as permissions you can attach to a profile.

## Variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `tenant_name` | — | Tenant subdomain |
| `saml_metadata_document_xml_content` | — | SAML metadata XML (contents) |
| `deploy_aws_invalidation_feature` | `true` | Session-invalidation permissions on `policy/britive/managed/*` |
| `deploy_access_builder` | `false` | Access Builder permissions on `role/britive/managed/*` |
| `deploy_ai_identity_scanning` | `false` | Attach `AmazonBedrockReadOnly` |
| `max_session_duration` | `3600` | Integration role session length (seconds) |
| `deploy_sample_roles` | `false` | Four demonstration JIT roles |
| `region` | `us-east-1` | Provider region (IAM is global) |

## Protecting the Britive-managed paths

With session invalidation enabled, apply the SCP in
[`../../../cloudformation/aws/scp/`](../../../cloudformation/aws/scp/) from
the management account so only the integration role can modify
`policy/britive/managed/*`.

## Update and remove

Re-run `terraform apply` with new values — for example after a SAML
certificate rotation, pass the new metadata file. `terraform destroy` removes
everything, including the sample roles; remove the AWS application from
Britive first.
