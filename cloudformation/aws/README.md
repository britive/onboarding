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
| AWS Identity Center (`DeployIdentityCenter`) | inline | The `identitystore`, `sso`, `organizations` and `iam:*Policy*` actions the **AWS Identity Center** application needs. Management account only; see [below](#aws-identity-center-and-aws-account-access) |
| AWS Account Access (`DeployAccountAccess` + `AccountAccessApplicationArn`) | inline | `account-access:ListApplications` plus entitlement create/delete/list on the one application. Management account only |
| Sample JIT roles (`DeploySampleRoles`) | `Readonly-admin-role`, `Poweruser-role`, `EC2-Fullaccess-role`, `S3-Fullaccess-role` | Demonstrations; same trust policy as any role Britive brokers. Not usable with AWS Account Access (different trust, see below) |

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
   ./generate-parameters.sh acme britive-saml-metadata.xml --identity-center \
     --account-access arn:aws:account-access:<region>:<account>:application/<id>   # management account
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

## AWS Identity Center and AWS Account Access

Two more application types use the **management account's** identity provider
and integration role — Britive's guides say to add their permissions to the
same role, and the template does exactly that when you set the flags. Nothing
is deployed to member accounts for them; with
[`stackset-templates/`](stackset-templates/) leave both flags `false`.

| Application | Lets Britive | Docs |
| ----------- | ------------ | ---- |
| **AWS Identity Center** (`DeployIdentityCenter=true`) | Scan permission sets, groups and applications in IAM Identity Center and assign them just in time | [Guide](https://docs.britive.com/docs/aws-identity-center-onboarding-guide), [IAM role](https://docs.britive.com/docs/configuring-iam-roles-in-awsidentitycenter), [Onboarding](https://docs.britive.com/docs/onboarding-an-aws-identity-center-application-in-britive) |
| **AWS Account Access** (`DeployAccountAccess=true` + `AccountAccessApplicationArn`) | Create and delete account access manager entitlements to IAM roles in member accounts | [Guide](https://docs.britive.com/docs/aws-account-access), [Prerequisites](https://docs.britive.com/docs/prerequisites-aws-acctaccess), [Account access manager](https://docs.britive.com/docs/enable-account-access-manager), [IAM roles](https://docs.britive.com/docs/configuring-iam-roles-in-acctaccess) |

### Before enabling AWS Account Access

The account access manager must be enabled in the management account, in the
region where IAM Identity Center was first enabled (its *primary region*):

```bash
aws organizations enable-aws-service-access --service-principal account-access.amazonaws.com
# then open https://<primary-region>.console.aws.amazon.com/account-access/ and select Enable Account Access
```

On its **Settings** page copy the **application ARN** — it begins with
`arn:aws:account-access:` — and the **Application URL**. IAM Identity Center
also lists an application called *AWS account access* whose ARN begins with
`arn:aws:sso::`; that one is not supported and fails Britive's connection
test, which is why the template rejects it.

If your Identity Center instance uses a customer-managed KMS key, the account
access manager needs `kms:Decrypt` on it through the **key policy**; it is
not a permission of the integration role.

### Deploy

From the management account, with
[`single-account-stack/`](single-account-stack/) (or
[`organization-stackset/`](organization-stackset/), which passes the flags to
the management-account stack only):

```bash
./generate-parameters.sh acme britive-saml-metadata.xml --identity-center \
  --account-access arn:aws:account-access:<region>:<account>:application/<id>
aws cloudformation deploy --stack-name britive-integration \
  --template-file britive_integration_resources.yaml \
  --parameter-overrides file://parameters.json --capabilities CAPABILITY_NAMED_IAM
```

Both flags can be added to an existing stack later: regenerate the parameters
file and run the same command.

### The Britive application

**System Administration → Tenant Applications → Create Application → AWS
Identity Center** or **AWS Account Access**, with **Email mapping** under
Account Mapping, then on the Settings tab:

| Britive field | Value |
| ------------- | ----- |
| Identity Center Management Account ID / Management Account ID | `AccountId` output |
| Identity Provider Name | `BritiveSamlProviderName` output |
| Integration Role Name | `BritiveIntegrationRoleName` output (the name, not the ARN) |
| Duration of backend connection (hours) | `MaxSessionDurationSeconds` ÷ 3600 |
| Region | The region Britive calls STS in for temporary keys; use the Identity Center primary region |
| Login URL | The AWS access portal URL (IAM Identity Center → Settings; for Account Access, the Application URL from the account access manager) |
| AWS Account Access Application ARN (Account Access only) | `AccountAccessApplicationArn` output |

**Save and Test**, then **Scan**: permission sets, groups, accounts and
applications (Identity Center) or accounts and roles (Account Access) appear
under Permissions and Accounts.

### Roles Britive brokers through AWS Account Access

Unlike every other AWS application type, the roles checked out through AWS
Account Access are assumed by the **account access manager service**, not
through SAML. Each role you want to offer needs this statement in its trust
policy in its own account — no Britive identity provider, no `SAML:aud`:

```json
{
  "Effect": "Allow",
  "Principal": { "Service": "account-access.amazonaws.com" },
  "Action": ["sts:AssumeRole", "sts:SetContext"],
  "Condition": {
    "StringEquals": {
      "aws:SourceAccount": "<management-account-id>",
      "aws:SourceArn": "<account-access-manager-application-arn>"
    }
  }
}
```

A role missing either action is discovered by the scan but cannot be added to
a profile. The sample roles this template creates trust the SAML provider and
are therefore **not** usable here.

Identity Center profiles come in two shapes: a profile holding a **group or
application** must be associated at the root, while a **permission set**
profile can be scoped to the root, an OU or one account; the two kinds cannot
be mixed in one profile. To size a migration from permission sets,
[`../../python/aws/helper/aws_identityCenter_convert.py`](../../python/aws/helper/aws_identityCenter_convert.py)
lists the Identity Center-provisioned roles in an account with their last use.

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
| Stack rejected: `DeployAccountAccess=true requires AccountAccessApplicationArn` or the ARN fails its pattern | ARN missing, or the `arn:aws:sso::` one was used | Copy the ARN from the account access manager **Settings** page (`arn:aws:account-access:…`) |
| AWS Account Access **Save and Test** fails although the role has the policy | Account access manager not enabled in the primary region, or wrong region in the application | Enable it there first; set **Region** to the Identity Center primary region |
| An Account Access role is scanned but cannot be added to a profile | Its trust policy lacks `sts:SetContext` or the service principal | Add the trust statement shown above to the role in its account |
