# Britive provider example: tags, profiles and policies

The Britive side of an AWS onboarding, with the
[`britive/britive`](https://registry.terraform.io/providers/britive/britive/latest/docs)
provider: two tags, and three profiles on an AWS application that show the
three common policy shapes.

| Profile | Permission | Policy |
| ------- | ---------- | ------ |
| AWS Power User | `Poweruser-role` | Members of the team tag, **approval** by the approver tag (30 minutes to approve, valid 2 hours), extendable once |
| AWS S3 Full Access | `S3-Fullaccess-role` | Members of the team tag, no approval |
| AWS EC2 Full Access | `EC2-Fullaccess-role` | Members of the team tag, only from `allowed_ip_ranges` |

The permissions are the sample JIT roles the AWS templates in this
repository create ([CloudFormation](../../cloudformation/aws/) with
`DeploySampleRoles=true`, [Terraform](../aws/) with
`deploy_sample_roles = true`).

## Applications

The application itself can be created with the provider too, from the
outputs of the cloud-side stack, instead of in the console:

| Directory | Application type | Fed by |
| --------- | ---------------- | ------ |
| [`applications/aws/`](applications/aws/) | **AWS** (organization) | [`../aws/organization-stackset/`](../aws/organization-stackset/) or [`single-account-stack/`](../aws/single-account-stack/) outputs |
| [`applications/snowflake/`](applications/snowflake/) | **Snowflake** or **Snowflake Standalone** (`standalone = true`, one `britive_entity_environment` per account) | [`../snowflake/`](../snowflake/) outputs and key pair |

Scans are still started in the console. [`../google-cloud/britive-app/`](../google-cloud/britive-app/)
does the same for the GCP application types.

## Prerequisites

- Terraform >= 1.5; the provider (`~> 3.0`) is fetched by `terraform init`
- An AWS application in Britive that has been **scanned**, so the roles and
  the account environment exist; note the application name and the
  environment (account) name from the console
- An API token with rights over tags, profiles and policies

## Deploy

```bash
export BRITIVE_TENANT=https://your-tenant.britive-app.com
export BRITIVE_TOKEN=<API token>

cp terraform.tfvars.example terraform.tfvars   # application_name, environment_name, tag names, members
terraform init
terraform apply
```

Users in the team tag then see the three profiles in **My Access**; the
Power User checkout waits for someone in the approver tag.

## Variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `application_name` | `AWS Standalone` | The AWS application in Britive |
| `environment_name` | — | Account name as the scan shows it |
| `identity_provider_name` | `Britive` | Provider the tags live on (Terraform manages local tags only) |
| `team_tag_name` | `aws-developers` | Who may check out |
| `team_members` | `[]` | Usernames to put in the team tag |
| `approver_tag_name` | `aws-approvers` | Who approves the Power User profile |
| `allowed_ip_ranges` | `10.0.0.0/8,192.168.0.0/16` | Source restriction on the EC2 profile |

## Adapting it

- Other applications: change `application_name`, the `associations` value
  (an environment or environment group name) and the permission
  names/types (`role` for AWS, `Group` for Kubernetes and Okta, …) to what
  the scan lists.
- Approval over Slack or Teams: add the medium to `notificationMedium` and
  the channel IDs under `approvers`.
- Time-of-day restrictions: add `timeOfAccess` to the condition; see the
  provider's `britive_profile_policy` documentation.
- Keep `consumer = "papservice"` on every profile policy; other values
  silently break access.

## Remove

`terraform destroy` deletes the policies, permissions, profiles and tags
(members included).
