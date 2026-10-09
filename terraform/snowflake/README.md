# Snowflake integration (Terraform)

Creates what the Britive **Snowflake** or **Snowflake Standalone**
application needs in a Snowflake account: an account role with
`MANAGE GRANTS`, a service user that holds it with key-pair authentication,
and — for the organization application only — `ORGADMIN` on that role.

Product steps: [Configuring on the Snowflake application](https://docs.britive.com/docs/configuring-on-snowflake-application),
then onboarding the [Snowflake](https://docs.britive.com/docs/onboarding-snowflake-in-britive-application)
or [Snowflake organization](https://docs.britive.com/docs/onboarding-snowflake-org-application-in-britive)
application.

## Prerequisites

- Terraform >= 1.5 and the `snowflakedb/snowflake` provider (`~> 2.0`,
  fetched by `terraform init`)
- A Snowflake administrator with **key-pair authentication** for Terraform
  itself. Snowflake is retiring password-only logins, and the provider
  supports `SNOWFLAKE_JWT`:

  ```bash
  openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.ssh/snowflake_admin.p8 -nocrypt
  openssl rsa -in ~/.ssh/snowflake_admin.p8 -pubout -out ~/.ssh/snowflake_admin.pub
  # as ACCOUNTADMIN, register the key body (no header/trailer, one line):
  # ALTER USER TERRAFORM_ADMIN SET RSA_PUBLIC_KEY='MIIBIjANBg...';
  ```

- A **second** key pair for Britive's service user. Only the public half is
  read here; the private half is uploaded to the Britive application:

  ```bash
  openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.ssh/britive_snowflake.p8 -nocrypt
  openssl rsa -in ~/.ssh/britive_snowflake.p8 -pubout -out ~/.ssh/britive_snowflake.pub
  ```

Keep every key outside the repository (`*.p8`, `*.pem` and `*.pub` are not
tracked here; `terraform.tfvars` is ignored).

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars    # account identifier, admin user, key paths
terraform init
terraform plan
terraform apply
```

`grant_orgadmin = true` (organization application) also needs
`snowflake_admin_role = "ORGADMIN"`.

## Configure the application in Britive

**System Administration → Tenant Applications → Create Application →
Snowflake** (or **Snowflake Standalone**) — or create it with the provider
from [`../britive/applications/snowflake/`](../britive/applications/snowflake/) — then:

| Britive field | From |
| ------------- | ---- |
| Account ID | `terraform output account_identifier` |
| Username | `terraform output username` (`BRITIVEUSER`) |
| Role | `terraform output role` (`BRITIVEROLE`) |
| Private key / public key | `~/.ssh/britive_snowflake.p8` and `.pub` (and the passphrase, if any) |

## Variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `snowflake_organization`, `snowflake_account` | — | Account identifier parts |
| `snowflake_admin_user` | — | Terraform's user (key-pair auth) |
| `snowflake_admin_private_key_file` | `~/.ssh/snowflake_admin.p8` | Its PKCS#8 private key |
| `snowflake_admin_private_key_passphrase` | `null` | If the key is encrypted |
| `snowflake_admin_role` | `ACCOUNTADMIN` | `ORGADMIN` when granting ORGADMIN |
| `britive_role_name` | `BRITIVEROLE` | Role for Britive |
| `britive_user_name` | `BRITIVEUSER` | Service user for Britive |
| `britive_public_key_file` | — | Public key of Britive's key pair |
| `grant_orgadmin` | `false` | Organization application only |

## Remove

`terraform destroy` drops the user, the grants and the role. Remove the
Snowflake application from Britive first.
