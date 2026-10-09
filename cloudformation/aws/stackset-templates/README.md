# Member accounts with StackSets

Deploy [`../britive_integration_resources.yaml`](../britive_integration_resources.yaml)
to every account under one or more OUs with a service-managed CloudFormation
StackSet. Auto-deployment onboards accounts that join the OUs later.

**The management account is not included.** Service-managed StackSets never
deploy to it, and the Britive **AWS** application type needs the identity
provider and integration role there. Deploy
[`../single-account-stack/`](../single-account-stack/) in the management
account as well — or use [`../organization-stackset/`](../organization-stackset/),
which does both from one stack.

Read [`../README.md`](../README.md) first for what the template creates and
the Britive application fields.

## Prerequisites

- Credentials for the management account, or for a
  [delegated administrator](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-delegated-admin.html)
  (add `--call-as DELEGATED_ADMIN` to every command below)
- Trusted access for StackSets:
  `aws organizations enable-aws-service-access --service-principal member.org.stacksets.cloudformation.amazonaws.com`
- The target IDs: `aws organizations list-roots` (root `r-xxxx`) or
  `aws organizations list-organizational-units-for-parent --parent-id r-xxxx`
- A parameters file: `cd .. && ./generate-parameters.sh acme britive-saml-metadata.xml`
  (without `--identity-center` / `--account-access`: those permissions belong
  in the management account only)

## Deploy

```bash
cd ..
aws cloudformation create-stack-set \
  --stack-set-name britive-integration \
  --template-body file://britive_integration_resources.yaml \
  --parameters file://parameters.json \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation create-stack-instances \
  --stack-set-name britive-integration \
  --deployment-targets OrganizationalUnitIds=r-xxxx \
  --regions us-east-1 \
  --operation-preferences FailureToleranceCount=10,MaxConcurrentCount=10,RegionConcurrencyType=PARALLEL
```

IAM is global; one region is enough. Replace `r-xxxx` with specific OU IDs
(`OrganizationalUnitIds=ou-aaaa-xxxxxxxx,ou-bbbb-yyyyyyyy`) to limit scope.

Console: **CloudFormation → StackSets → Create StackSet → Upload a template
file**, service-managed permissions, paste the metadata XML, choose the OUs,
enable automatic deployment, one region, submit.

## Watch it roll out

```bash
aws cloudformation list-stack-instances --stack-set-name britive-integration \
  --query 'Summaries[].{account:Account,status:Status,reason:StatusReason}' --output table
```

## Configure Britive

Deploy the management account first, then **System Administration → Tenant
Applications → Create Application → AWS** with the management account's
outputs. **Save and Test** lists every member account the StackSet reached.

## Update

```bash
cd .. && ./generate-parameters.sh acme new-britive-saml-metadata.xml
aws cloudformation update-stack-set \
  --stack-set-name britive-integration \
  --template-body file://britive_integration_resources.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

The update is applied to every instance.

## Delete

```bash
aws cloudformation delete-stack-instances --stack-set-name britive-integration \
  --deployment-targets OrganizationalUnitIds=r-xxxx --regions us-east-1 --no-retain-stacks
# wait until list-stack-instances is empty, then
aws cloudformation delete-stack-set --stack-set-name britive-integration
```

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Instance `FAILED`: `already exists` | The account already has a role or provider with that name | Delete it in that account or import it; `--operation-preferences FailureToleranceCount` lets the rest continue |
| `AccessDenied` creating the StackSet | Not the management account / delegated admin, or trusted access off | See prerequisites |
| New accounts not onboarded | Auto-deployment off, or account outside the targeted OUs | `aws cloudformation describe-stack-set --stack-set-name britive-integration --query StackSet.AutoDeployment` |
| Save and Test fails in Britive | Management account not deployed | Deploy `../single-account-stack/` there |
