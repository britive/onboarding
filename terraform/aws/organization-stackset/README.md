# Britive AWS integration — whole organization (Terraform)

One `terraform apply` onboards an AWS Organization:

- the **management account** gets the SAML identity provider and integration
  role directly (service-managed StackSets cannot deploy there, and the
  Britive **AWS** application type needs them there), through
  [`../modules/britive-integration`](../modules/britive-integration/);
- every **member account** under the OUs you list gets the same resources
  from a service-managed CloudFormation StackSet, with auto-deployment so
  accounts that join later are onboarded without another apply.

The StackSet uses the template in
[`../../../cloudformation/aws/organization-stackset/britive_integration_resources.yaml`](../../../cloudformation/aws/organization-stackset/britive_integration_resources.yaml)
read straight from this repository; nothing is uploaded to S3.

## Prerequisites

- Terraform >= 1.5
- Credentials for the **management account**, or for a
  [delegated administrator](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-delegated-admin.html)
  with `call_as = "DELEGATED_ADMIN"`
- Trusted access for CloudFormation StackSets enabled in AWS Organizations
  (`aws organizations enable-aws-service-access --service-principal member.org.stacksets.cloudformation.amazonaws.com`)
- The SAML metadata XML from your tenant: **System Administration → Security
  → SAML Configurations → Download SAML Metadata**
- The root ID (`r-xxxx`) or the OU IDs to deploy to: `aws organizations list-roots`
- Product steps: [Britive AWS onboarding guide](https://docs.britive.com/docs/application-onboarding-guides)

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars   # tenant_name, organizational_unit_ids, flags
terraform init
terraform apply -var="saml_metadata_document_xml_content=$(cat britive-saml-metadata.xml)"
```

Watch the StackSet roll out:

```bash
aws cloudformation list-stack-instances --stack-set-name britive-resources-<tenant> \
  --query 'Summaries[].{account:Account,status:Status,reason:StatusReason}' --output table
```

## Configure the application in Britive

**System Administration → Tenant Applications → Create Application → AWS**,
then map the outputs:

| Britive field | Terraform output |
| ------------- | ---------------- |
| Management Account ID | `management_account_id` |
| Identity Provider Name | `identity_provider_name` |
| Integration Role Name | `integration_role_name` (the name, not the ARN; identical in every account) |
| Duration of backend connection (hours) | `backend_connection_duration_hours` |
| Region | the region you deploy workloads in |

**Save and Test** scans the organization and lists every member account the
StackSet reached.

## Variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `tenant_name` | — | Tenant subdomain |
| `saml_metadata_document_xml_content` | — | SAML metadata XML (contents) |
| `organizational_unit_ids` | — | Root or OU IDs for the StackSet |
| `deploy_aws_invalidation_feature` | `true` | Session-invalidation permissions, management and member accounts |
| `deploy_access_builder` | `false` | Access Builder permissions, management account only |
| `deploy_ai_identity_scanning` | `false` | `AmazonBedrockReadOnly`, management account only |
| `max_session_duration` | `3600` | Management-account integration role (member accounts use the template's 3600) |
| `region` | `us-east-1` | Provider and StackSet instance region |
| `call_as` | `SELF` | `DELEGATED_ADMIN` from a delegated administrator |
| `failure_tolerance_count` / `max_concurrent_count` | `10` / `10` | StackSet operation preferences |

## Protecting the Britive-managed paths

Apply the SCP in [`../../../cloudformation/aws/scp/`](../../../cloudformation/aws/scp/)
to the same OUs so only the integration role can modify
`policy/britive/managed/*` in member accounts.

## Update and remove

Re-running `apply` with a new metadata file updates the management account
and the StackSet (every instance). `terraform destroy` deletes the StackSet
instances from all member accounts first, then the management-account
resources; remove the AWS application from Britive beforehand.
