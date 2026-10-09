# Single account

Deploy [`../britive_integration_resources.yaml`](../britive_integration_resources.yaml)
as a stack in one account: a standalone account, a proof of concept, or the
**management account** of an organization (service-managed StackSets cannot
target it; see [`../stackset-templates/`](../stackset-templates/) for the
members).

Read [`../README.md`](../README.md) first for what the template creates and
the Britive application fields.

## Deploy

Download the SAML metadata (**System Administration → Security → SAML
Configurations → Download SAML Metadata**) and generate the parameters file:

```bash
cd ..
./generate-parameters.sh acme britive-saml-metadata.xml                 # add --sample-roles for a demo
```

### CLI

```bash
aws cloudformation deploy \
  --stack-name britive-integration \
  --template-file britive_integration_resources.yaml \
  --parameter-overrides file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation describe-stacks --stack-name britive-integration \
  --query 'Stacks[0].Outputs' --output table
```

### Console

**CloudFormation → Create stack → With new resources → Upload a template
file** → `britive_integration_resources.yaml`. Paste the whole metadata XML
into *SAML metadata XML* (the console accepts multi-line input), set the
flags, acknowledge *IAM resources with custom names*, submit. The stack takes
about a minute.

## Configure Britive

**System Administration → Tenant Applications → Create Application → AWS
Standalone** (or **AWS** when this is the management account): enter
`AccountId`, `BritiveSamlProviderName`, `BritiveIntegrationRoleName` and
`MaxSessionDurationSeconds ÷ 3600` from the outputs, then **Save and Test**.

In the management account the same stack can also serve the **AWS Identity
Center** and **AWS Account Access** application types: add `--identity-center`
and/or `--account-access <arn>` to `generate-parameters.sh`. See
[`../README.md`](../README.md#aws-identity-center-and-aws-account-access) for
the prerequisites (enabling the account access manager) and the application
fields.

## Verify

```bash
aws iam get-role --role-name britive-acme-integration-role --query 'Role.{arn:Arn,max:MaxSessionDuration}'
aws iam list-saml-providers
```

## Update and delete

```bash
# new SAML certificate: regenerate parameters.json, then
aws cloudformation deploy --stack-name britive-integration \
  --template-file britive_integration_resources.yaml \
  --parameter-overrides file://parameters.json --capabilities CAPABILITY_NAMED_IAM

aws cloudformation delete-stack --stack-name britive-integration
```

Remove the application from Britive before deleting the stack. Deleting
needs `iam:DeleteRole`, `iam:DeleteRolePolicy`, `iam:DetachRolePolicy` and
`iam:DeleteSAMLProvider` in addition to the create permissions.
