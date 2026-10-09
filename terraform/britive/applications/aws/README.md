# Britive application: AWS (organization)

Creates the **AWS** application in Britive from the outputs of the AWS stack
that put the identity provider and integration role in the management
account — the last step of
[`../../../aws/organization-stackset/`](../../../aws/organization-stackset/)
or [`../../../aws/single-account-stack/`](../../../aws/single-account-stack/)
(or the [CloudFormation](../../../../cloudformation/aws/) equivalents), done
in Terraform instead of the console.

Console equivalent: [Onboarding an AWS application](https://docs.britive.com/docs/onboarding-an-aws-application).

| Britive field | Variable | AWS stack output |
| ------------- | -------- | ---------------- |
| Management Account ID | `management_account_id` | `management_account_id` (organization) / `account_id` (single account) |
| Identity Provider Name | `identity_provider_name` | `identity_provider_name` / `saml_provider_name` |
| Integration Role Name | `integration_role_name` | `integration_role_name` |
| Duration of the backend AWS connection (hours) | `backend_connection_duration_hours` | `backend_connection_duration_hours` |
| Region | `region` | the region you deploy workloads in |
| Show AWS Account Numbers | `show_aws_account_numbers` | |
| Account Mapping | `account_mapping_attribute` | |
| Profile Settings: maximum session duration | `max_session_duration_for_profiles` (seconds) | |

## Deploy

```bash
export BRITIVE_TENANT=https://your-tenant.britive-app.com
export BRITIVE_TOKEN=<API token>

cp terraform.tfvars.example terraform.tfvars   # paste the AWS stack outputs
terraform init
terraform apply
```

Then, in the console, open the application (**System Administration →
Tenant Applications**) and run **Scan**: the provider creates the
application and its settings but does not trigger scans. Profiles can only
be associated with accounts and roles the scan found —
[`../../`](../../) shows profiles, permissions and policies on this
application.

## Notes

- `sessionDuration` must equal the integration role's maximum session
  duration in hours (`MaxSessionDuration` ÷ 3600 on the AWS side); a
  mismatch fails the connection test.
- The AWS Standalone application type takes the same connection properties
  but holds accounts as `britive_entity_environment` entities; the
  provider's documentation shows the entity properties. It is not covered
  here because its application-level property names are not documented.
- Session invalidation, Access Builder and AI identity scanning are
  enabled on the application in the console after the AWS side is deployed
  with the matching flags.
- `terraform destroy` deletes the application and everything under it
  (profiles, policies, scan data).
