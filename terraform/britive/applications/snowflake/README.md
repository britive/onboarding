# Britive application: Snowflake and Snowflake Standalone

Creates the Britive application for Snowflake after
[`../../../snowflake/`](../../../snowflake/) created the role, the service
user and the key pair — the console step done in Terraform. One module, two
application types:

| `standalone` | Application type | Shape | Console guide |
| ------------ | ---------------- | ----- | ------------- |
| `false` (default) | **Snowflake** | Connection properties on the application; Britive discovers the organization's accounts and, with `copy_settings_to_all_accounts`, reuses the same user, role and keys for all of them | [Onboarding the Snowflake organization application](https://docs.britive.com/docs/onboarding-snowflake-org-application-in-britive) |
| `true` | **Snowflake Standalone** | The application is a shell; each account in `accounts` becomes a `britive_entity_environment` with its own connection properties | [Onboarding the Snowflake Standalone application](https://docs.britive.com/docs/onboarding-snowflake-in-britive-application) |

The organization application needs `ORGADMIN` on the Britive role
(`grant_orgadmin = true` in `../../../snowflake`); the standalone one does not.

| Britive field | Variable | From `../../../snowflake` |
| ------------- | -------- | ------------------------- |
| Account ID | `account_identifier` / `accounts[*].account_identifier` | `terraform output account_identifier` |
| Login URL | `login_url` (`{accountId}` is substituted) | |
| Username, Custom Role | `username`, `role` (uppercase) | `terraform output username`, `role` |
| Public and private keys, password of the private key | `public_key_file`, `private_key_file`, `private_key_passphrase` | `~/.ssh/britive_snowflake.pub` / `.p8` |
| Use login name for account mapping | `use_login_name_for_account_mapping` | |
| Skip collecting schema level privileges | `skip_schema_level_privileges` | |
| Use same user, role and keys for all accounts (organization only) | `copy_settings_to_all_accounts` | |
| Account Mapping | `account_mapping_attribute` | |
| Profile Settings: maximum session duration | `max_session_duration_for_profiles` (seconds) | |

## Deploy

```bash
export BRITIVE_TENANT=https://your-tenant.britive-app.com
export BRITIVE_TOKEN=<API token>

cp terraform.tfvars.example terraform.tfvars   # standalone, account identifier(s), key paths
terraform init
terraform apply
```

Then open the application in the console (**System Administration → Tenant
Applications**), **Save and Test**, and **Scan**; the provider does not
trigger scans. Profiles then grant Snowflake roles to users —
[`../../`](../../) shows the profile, permission and policy pattern.

## Notes

- The private key is read from disk at plan time and stored in the Terraform
  state. Keep the state where you keep secrets (encrypted remote backend).
  The provider does not detect key changes made in the console.
- Changing `standalone` replaces the application: profiles and scan data
  under it are lost.
- `terraform destroy` deletes the application and everything under it.
