# AWS integration with Python

`setup_aws.py` creates what Britive needs in an AWS account — the SAML
identity provider and the integration role — the same resources as the
[CloudFormation](../../cloudformation/aws/) and [Terraform](../../terraform/aws/)
templates, for when a script fits your workflow better. It reads the SAML
metadata straight from the tenant through the Britive API, so there is
nothing to download.

Product steps: [Britive AWS onboarding guide](https://docs.britive.com/docs/application-onboarding-guides).

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env            # BRITIVE_TENANT, BRITIVE_API_TOKEN
export AWS_PROFILE=<profile for the target account>
```

The API token needs permission to read the tenant's SAML metadata
(`security.saml.metadata`). AWS credentials need `iam:CreateSAMLProvider`,
`iam:ListSAMLProviders`, `iam:CreateRole`, `iam:GetRole`,
`iam:UpdateAssumeRolePolicy`, `iam:AttachRolePolicy`, `iam:PutRolePolicy`.

## Run

```bash
python3 setup_aws.py --idp --role                        # provider + role, invalidation on
python3 setup_aws.py --idp --role --access-builder       # + Access Builder permissions
python3 setup_aws.py --role --no-invalidation            # provider already exists
python3 setup_aws.py --role --identity-center \
  --account-access arn:aws:account-access:<region>:<account>:application/<id>   # management account
python3 setup_aws.py --help
```

| Option | Default | Effect |
| ------ | ------- | ------ |
| `-i`, `--idp` | — | Create the SAML provider (skips if it exists) |
| `-r`, `--role` | — | Create the integration role; idempotent, refreshes the trust policy if the role exists |
| `--tenant` | `BRITIVE_TENANT` | Tenant subdomain |
| `--idp-name` | `britive-<tenant>` | Provider name |
| `--role-name` | `britive-<tenant>-integration-role` | Role name |
| `--max-session-duration` | `3600` | Role session length in seconds; enter the same value in hours in Britive |
| `--no-invalidation` | off | Skip the `policy/britive/managed/*` permissions |
| `-m`, `--access-builder` | off | Add `iam:*Role*` on `role/britive/managed/*` |
| `--ai-scanning` | off | Attach `AmazonBedrockReadOnly` |
| `--identity-center` | off | Management account only: inline policy `britive-identity-center` with the permissions the **AWS Identity Center** application needs |
| `--account-access <arn>` | off | Management account only: inline policy `britive-account-access` for the **AWS Account Access** application; the ARN comes from the account access manager **Settings** page (`arn:aws:account-access:…`, not `arn:aws:sso::`) |

The script prints the four values to enter in **System Administration →
Tenant Applications → Create Application → AWS Standalone**: account ID,
identity provider name, integration role name, duration of backend
connection. With `--identity-center` or `--account-access` it also prints the
extra fields of those application types; the prerequisites (enabling the
account access manager, the trust policy Account Access roles need) are in
[`../../cloudformation/aws/README.md`](../../cloudformation/aws/README.md#aws-identity-center-and-aws-account-access).
`--role` is idempotent, so the two flags can be added to an existing role
later.

## Helper: `helper/aws_identityCenter_convert.py`

Lists the IAM roles AWS Identity Center provisioned in the account
(`/aws-reserved/sso.amazonaws.com/<region>/…`) with their permission set
name and last-used date into `<account>.csv`, as a scoping aid when
migrating permission sets to Britive profiles.

```bash
python3 helper/aws_identityCenter_convert.py --region us-west-2
```
