# Britive AWS integration — CloudFormation

One template, [`britive_integration_resources.yaml`](britive_integration_resources.yaml),
creates what Britive needs in an AWS account: the SAML identity provider and
the integration role, with optional permissions for session invalidation,
Access Builder and AI identity scanning, and optional sample JIT roles. The
directories below are the ways to deploy it.

| Option | Use it for | Scope |
| ------ | ---------- | ----- |
| [`single-account-stack/`](single-account-stack/) | A standalone account, a POC, or the **management account** of an organization | 1 account |
| [`stackset-templates/`](stackset-templates/) | Member accounts under one or more OUs, with auto-deployment for accounts that join later | Member accounts |
| [`organization-stackset/`](organization-stackset/) | Management account **and** member accounts from one stack (nested stack + StackSet) | Whole organization |
| [`full-lab-setup/`](full-lab-setup/) | A disposable demo: integration, sample roles, Linux/Windows/MySQL targets in their own VPC | 1 sandbox account |

Also here: [`scp/`](scp/), the Service Control Policy Britive recommends so
only the integration role can modify the Britive-managed IAM paths, and
[`generate-parameters.sh`](generate-parameters.sh), which writes a parameters
file with the SAML metadata correctly escaped.

Prerequisites and the product side are documented in the
[Britive AWS onboarding guide](https://docs.britive.com/docs/application-onboarding-guides);
each README here maps the stack outputs onto the fields of the Britive
application. Terraform equivalents: [`../../terraform/aws/`](../../terraform/aws/).

## What the template creates

| Resource | Name | Notes |
| -------- | ---- | ----- |
| SAML identity provider | `britive-<tenant>` | From the metadata XML you download from the tenant |
| Integration role | `britive-<tenant>-integration-role` | `IAMReadOnlyAccess` + `AWSOrganizationsReadOnlyAccess`; trusts the provider for `sts:AssumeRoleWithSAML`, `sts:SetSourceIdentity`, `sts:TagSession` with `SAML:aud` pinned |
| Invalidation policy (`DeployAwsInvalidationFeature`, default on) | inline | `iam:*Policy*` on `policy/britive/managed/*` in this account |
| Access Builder policy (`DeployAccessBuilder`) | inline | `iam:*Role*` on `role/britive/managed/*` in this account |
| AI identity scanning (`DeployAiIdentityScanning`) | managed | `AmazonBedrockReadOnly` |
| Sample JIT roles (`DeploySampleRoles`) | `Readonly-admin-role`, `Poweruser-role`, `EC2-Fullaccess-role`, `S3-Fullaccess-role` | Demonstrations; same trust policy as any role Britive brokers |

`MaxSessionDuration` (default 3600 s) is what you enter, in hours, as
*Duration of backend connection* in the Britive application.

## Before you start

1. **Tenant subdomain**: `acme` for `https://acme.britive-app.com`.
2. **SAML metadata XML**: **System Administration → Security → SAML
   Configurations → Download SAML Metadata**. It identifies your tenant, so
   keep it out of version control (`*.xml` here is ignored), but it contains
   only the identity provider's public signing certificate.
3. **Parameters file**: the metadata must be JSON-escaped, which is tedious by
   hand. From this directory:

   ```bash
   ./generate-parameters.sh acme britive-saml-metadata.xml            # core only
   ./generate-parameters.sh acme britive-saml-metadata.xml --sample-roles --access-builder
   # writes ./parameters.json (gitignored); use it with any option below
   ```

4. **IAM permissions** to create roles, policies and SAML providers in the
   target account(s); StackSet options also need the management account or a
   delegated administrator with trusted access enabled for CloudFormation
   StackSets.

## After deployment: the Britive application

**System Administration → Tenant Applications → Create Application → AWS**
(an organization) or **AWS Standalone** (a single account), then:

| Britive field | Stack output |
| ------------- | ------------ |
| Management Account ID / Account ID | `AccountId` |
| Identity Provider Name | `BritiveSamlProviderName` |
| Integration Role Name | `BritiveIntegrationRoleName` (the name, not the ARN) |
| Duration of backend connection (hours) | `MaxSessionDurationSeconds` ÷ 3600 |
| Region | the region you deploy workloads in |

**Save and Test** runs the first scan; sample roles (if created) appear as
permissions you can attach to a profile.

## Protecting the Britive-managed paths

With session invalidation or Access Builder enabled, apply the SCP in
[`scp/`](scp/) from the management account so nothing but the integration
role can modify `policy/britive/managed/*` and `role/britive/managed/*`.

## Updating

A new SAML certificate means a new metadata file: regenerate the parameters
file and run `update-stack` / `update-stack-set` with it. Parameters you do
not change can be passed as `ParameterKey=…,UsePreviousValue=true`.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `Invalid SAML metadata` | Not the full XML, or hand-escaped wrongly | Use `generate-parameters.sh`; `xmllint --noout file.xml` to check the source |
| `Role … already exists` | A previous deployment left the role behind | Delete it (detach managed policies and delete inline policies first) or use a different tenant name |
| Save and Test fails in Britive | Integration role missing in the **management** account | Service-managed StackSets skip it; deploy `single-account-stack/` there, or use `organization-stackset/` |
| Checkout of your own role fails after enabling Source Identity | Role trust policy lacks `sts:SetSourceIdentity` | Add it (and `sts:TagSession`); the sample roles show the full trust policy |
| StackSet reports `trusted access` errors | Trusted access for StackSets not enabled in Organizations | `aws organizations enable-aws-service-access --service-principal member.org.stacksets.cloudformation.amazonaws.com` |
