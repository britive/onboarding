# Britive - Google Workspace application with Terraform

Sets up what Britive needs to manage just-in-time access **to Google Workspace itself** — admin roles and group memberships — through the Britive **Google Workspace** application type, and optionally creates the application. This is not the Google Cloud integration; for that see [../google-cloud](../google-cloud/README.md).

Product steps: [Google Workspace onboarding guide](https://docs.britive.com/docs/google-workspace-connector-onboarding-guide), [prerequisites](https://docs.britive.com/docs/pre), [domain-wide delegation](https://docs.britive.com/docs/domain-wide-delegation-gw), [onboarding the application](https://docs.britive.com/docs/onboarding-gws).

## What gets created

| Where | What | By |
| --- | --- | --- |
| Google Cloud | A project (or an existing one) with the Admin SDK API enabled, the service account `britive-workspace@<project>.iam.gserviceaccount.com` and its key, written to `keys/key.json` (mode 0600, git-ignored) | this directory |
| Google Workspace | Domain-wide delegation of the seven scopes the guide lists to that service account | **you**, in the Admin console; `deploy.sh` prints the client ID and scopes and waits |
| Google Workspace | The **Britive API Role** (organisational units, users and groups read; groups update) and the user `britive-integration@<domain>` holding it, which Britive impersonates | [../google-workspace](../google-workspace/README.md), reused with this root's key |
| Britive | The Google Workspace application, filled in from the above | [britive-app/](britive-app/README.md), optional |

Britive signs in as the service account, impersonates the admin user through domain-wide delegation, and reads or changes roles and group memberships with the Admin SDK. At checkout it assigns the admin role or group membership named by the profile; at checkin it removes it. With *Create user account for super admin role* on, a super admin checkout creates a separate `<user>_britive@<domain>` account that is suspended at checkin.

## Before you start

**Tools:** Terraform 1.5 or later, the Google Cloud CLI (`gcloud`), `jq`.

**Google Cloud rights** for the person running Terraform: create a project (Project Creator on the organisation or folder) or, with `create_project = false`, enable APIs and create service accounts and keys in the existing project. Organisation policy `iam.disableServiceAccountKeyCreation` must allow the key; this application type has no keyless mode.

**Google Workspace:** a super administrator, to grant domain-wide delegation and for `../google-workspace` to act as (`workspace_impersonation_email` in its `terraform.tfvars`). The admin user Britive impersonates consumes a Workspace licence.

**Britive:** for the optional application step, an API token with rights over Applications.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars                                  # project_id, organization_id, workspace_domain
cp ../google-workspace/terraform.tfvars.example ../google-workspace/terraform.tfvars   # customer ID, domain, super admin to act as

export BRITIVE_TENANT=https://your-tenant.britive-app.com   # optional: also create the application
export BRITIVE_TOKEN=<API token>

./deploy.sh
```

`deploy.sh` signs you in to Google if Application Default Credentials are missing, applies this directory, prints the delegation client ID and scopes and waits for you to add them under **Security → Access and data control → API controls → Manage Domain Wide Delegation**, applies `../google-workspace` with this root's key (retrying the plan for up to 10 minutes while delegation takes effect), then applies `britive-app/` if the Britive variables are set.

Afterwards: sign in once as the admin user (`terraform -chdir=../google-workspace output -raw initial_password`) so Workspace's terms are accepted — the [custom user prerequisite](https://docs.britive.com/docs/cis-custom-user) — then, in the Britive console, open the application, **Save and Test**, and **Scan**.

Running by hand is the same order: `terraform apply` here, grant delegation, `terraform -chdir=../google-workspace apply -var service_account_key_file=$(pwd)/keys/key.json`, then `britive-app/`.

## Values for the Britive console

If you create the application in the console instead of with `britive-app/`:

| Britive field | Value |
| --- | --- |
| Google Workspace Admin Email | `terraform -chdir=../google-workspace output -raw gsuite_admin_email` |
| Service Account Credentials (JSON) | contents of `keys/key.json` |
| Login URL | `https://admin.google.com`, or your custom console URL |
| Create user account for super admin role, Scan Roles, Scan Groups, SSO Settings, Account Mapping | as you need them; [britive-app/](britive-app/README.md) lists the equivalents |

## Delegation scopes

The guide lists seven; `admin.directory.rolemanagement` is only needed when super admin roles are granted through profiles, and is also what lets `../google-workspace` create the admin role through this service account. Drop it from the delegation entry afterwards if you do not grant admin roles, and re-add it before `terraform destroy`.

```text
https://www.googleapis.com/auth/admin.directory.user
https://www.googleapis.com/auth/cloud-platform
https://www.googleapis.com/auth/admin.directory.group
https://www.googleapis.com/auth/admin.directory.group.member
https://www.googleapis.com/auth/admin.directory.rolemanagement
https://www.googleapis.com/auth/admin.directory.customer.readonly
https://www.googleapis.com/auth/admin.directory.domain.readonly
```

## Remove

```bash
./destroy.sh
```

Removes the Britive application, the Workspace role and user, then the Google Cloud resources. The project has `deletion_policy = PREVENT` unless `allow_project_deletion = true`.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Key creation is not allowed on this service account` | `iam.disableServiceAccountKeyCreation` enforced | Grant an exception on the project; this application type needs a key |
| Workspace plan keeps failing with `unauthorized_client` | Delegation not saved, wrong client ID or scopes, or not yet in effect | Compare with what `deploy.sh` printed; changes take minutes |
| **Save and Test** fails with a 403 from the Admin SDK | Admin user lacks the Britive API Role, or has never signed in | Check the role assignment; sign in once as the user |
| Scan shows no roles or groups | *Scan Roles* / *Scan Groups* off on the application | Enable them (`scan_roles`, `scan_groups`) and scan again |
| Super admin checkout fails | `rolemanagement` scope removed from the delegation entry | Re-add it |
| `invalid character found in catalogAppDisplayName` | Punctuation in the application name | Letters, digits and spaces only |
