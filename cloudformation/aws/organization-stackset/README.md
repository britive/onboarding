# Whole organization in one stack

[`deploy_britive_integration_resources.yaml`](deploy_britive_integration_resources.yaml)
is a wrapper that deploys [`../britive_integration_resources.yaml`](../britive_integration_resources.yaml)
twice from the management account:

- as a **nested stack** in the management account itself (service-managed
  StackSets cannot target it, and the Britive **AWS** application needs the
  resources there), and
- as a **service-managed StackSet** with auto-deployment to every member
  account under the OUs you list.

Both need the template in an S3 bucket in the management account, in the
same region as the stack. The Terraform version of this option
([`../../../terraform/aws/organization-stackset/`](../../../terraform/aws/organization-stackset/))
reads the template from the repository and needs no bucket.

Read [`../README.md`](../README.md) first for what the template creates and
the Britive application fields.

## Prerequisites

- Credentials for the management account (or a StackSets delegated
  administrator, with `CallAs=DELEGATED_ADMIN`)
- Trusted access for StackSets:
  `aws organizations enable-aws-service-access --service-principal member.org.stacksets.cloudformation.amazonaws.com`
- The root ID (`aws organizations list-roots`) or OU IDs
- A bucket in the management account, same region as the stack; it does not
  need to be public

## Deploy

```bash
# 1. Upload the template
aws s3 cp ../britive_integration_resources.yaml s3://my-britive-templates/

# 2. Parameters: generate the escaped SAML value, then fill in the rest
cd .. && ./generate-parameters.sh acme britive-saml-metadata.xml -o /tmp/base.json && cd -
cp parameters.example.json parameters.json
# copy the SamlMetadataDocumentXmlContent value from /tmp/base.json into parameters.json,
# set S3BucketName, OrganizationalUnitIds, TenantName and the flags

# 3. Deploy
aws cloudformation deploy \
  --stack-name britive-organization \
  --template-file deploy_britive_integration_resources.yaml \
  --parameter-overrides file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
```

Console: **CloudFormation → Create stack → Upload a template file** →
`deploy_britive_integration_resources.yaml`; the parameters are grouped as
template location, organization targets, tenant, optional permissions.

## Watch the StackSet

```bash
aws cloudformation list-stack-instances --stack-set-name britive-resources-acme \
  --query 'Summaries[].{account:Account,status:Status,reason:StatusReason}' --output table
```

## Configure Britive

**System Administration → Tenant Applications → Create Application → AWS**,
with the outputs `ManagementAccountId`, `IdentityProviderName`,
`IntegrationRoleName` and `BackendConnectionDurationHours`. **Save and Test**
scans the organization.

## Parameters

| Parameter | Default | Description |
| --------- | ------- | ----------- |
| `S3BucketName` | — | Bucket holding the template (same region, management account) |
| `S3KeyForIamResourcesTemplate` | `britive_integration_resources.yaml` | Object key |
| `OrganizationalUnitIds` | — | Comma-separated OU IDs; `r-xxxx` for the whole organization |
| `Region` | `us-east-1` | Region for the member-account stacks |
| `CallAs` | `SELF` | `DELEGATED_ADMIN` from a delegated administrator |
| `TenantName`, `SamlMetadataDocumentXmlContent` | — | Tenant subdomain, metadata XML |
| `DeployAwsInvalidationFeature` | `true` | Everywhere |
| `DeployAccessBuilder`, `DeployAiIdentityScanning`, `DeploySampleRoles` | `false` | Everywhere |
| `DeployIdentityCenter`, `DeployAccountAccess`, `AccountAccessApplicationArn` | `false`, `false`, `""` | Management account only: the AWS Identity Center and AWS Account Access application types ([details](../README.md#aws-identity-center-and-aws-account-access)) |

## Update and delete

A new metadata file: regenerate the escaped value, update `parameters.json`,
run the same `deploy` command — the nested stack and every StackSet instance
are updated. If you change the template, upload it again first.

`delete-stack` on the wrapper removes the StackSet instances from every
member account, then the StackSet, then the management-account resources.
Remove the application from Britive first.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `TemplateURL must be an Amazon S3 URL` / 403 fetching the template | Bucket in another region, or the object is not there | Bucket and stack must share a region; `aws s3 ls s3://<bucket>/` |
| StackSet instances `FAILED: already exists` | A member account already has the role | Delete it there, then `update-stack-set` or wait for the next operation |
| Nested stack `ROLLBACK` with an IAM error | Capabilities not acknowledged | Pass `CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND` |
