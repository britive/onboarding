# Britive - Google Cloud integration with Terraform

Sets up everything Google Cloud needs before Britive can grant just-in-time access to it, and optionally creates the Britive application as well. Cloud integration only: no Britive Bridge or broker.

Two ways for Britive to authenticate are supported. Choose one with `integration_type`:

| | `wif` (recommended) | `key` (legacy) |
| --- | --- | --- |
| Britive application type | Google Cloud Platform WIF (`GCP WIF`) | Google Cloud Platform (`GCP`) |
| How Britive signs in | Presents an OpenID Connect token from your tenant to a workload identity pool and impersonates the service account. No secret is stored anywhere | Stores a long-lived service account key |
| Google Workspace | Not used | A Workspace admin user and domain-wide delegation, created by [../google-workspace](../google-workspace/README.md) |
| Blocked by `iam.disableServiceAccountKeyCreation` | No | Yes |

## What gets created

In Google Cloud (this directory):

- A project for the Britive service account (`project_id`), or an existing project when `create_project = false`.
- The APIs Britive calls: Cloud Resource Manager, IAM and Directory (`admin.googleapis.com`); with `wif`, also Security Token Service and IAM Credentials.
- The organisation custom role **Britive Integration Role** (`BritiveIntegrationRole`), with the permissions from Britive's prerequisites ([organization](https://docs.britive.com/docs/custom-role-in-gcp) / [projects only](https://docs.britive.com/docs/creating-a-custom-role-for-gcp-standalone-application)), plus the optional permission sets for BigQuery and Apigee constraints and AI identity scanning.
- The service account `britive-integration@<project_id>.iam.gserviceaccount.com`, granted the role on the organisation, or on one folder or project (`access_scope`).
- `wif`: a workload identity pool (`britive`) with an OIDC provider (`britive-oidc`) trusting `https://<tenant>/api/auth/sso/oauth2` with the default audience, and `roles/iam.serviceAccountTokenCreator` plus `roles/iam.workloadIdentityUser` on the service account for every identity in the pool.
- `key`: a service account key, written to `keys/key.json` (mode 0600, git-ignored).

In Britive ([britive-app](britive-app/README.md), optional): the application, filled in from the values above.

## Before you start

**Tools:** Terraform 1.5 or later, the Google Cloud CLI (`gcloud`), `jq`.

**Google Cloud permissions** for the person running Terraform:

| Role | On | Needed for |
| --- | --- | --- |
| Organization Role Administrator (`roles/iam.organizationRoleAdmin`) | Organisation | The custom role |
| Organization Administrator (`roles/resourcemanager.organizationAdmin`), or Folder IAM Admin / Project IAM Admin for a narrower `access_scope` | Organisation, folder or project | Granting the role |
| Project Creator (`roles/resourcemanager.projectCreator`) | Organisation or `folder_id` | A new project. The creator becomes its owner, which covers the APIs, the service account and the pool |
| Billing Account User (`roles/billing.user`) | Billing account | Only if `billing_account` is set |
| Owner, or Service Usage Admin + Service Account Admin + Workload Identity Pool Admin (`wif`) / Service Account Key Admin (`key`) | The project | Only when `create_project = false` |

Key mode also needs a Google Workspace super administrator, to grant domain-wide delegation and for Terraform to act as.

**Britive:** for the optional application step, an API token with rights over Applications.

**Organisation policies that can block this.** Check them on the project and on the access scope before you start:

| Constraint | Effect | What to do |
| --- | --- | --- |
| `iam.disableServiceAccountKeyCreation` | Refuses the key in `key` mode, and the temporary keys Britive issues when programmatic access is on. Enforced by default on newer organisations | Use `wif`, and leave `programmatic_access = false` in britive-app; or grant an exception on the project |
| `iam.allowedPolicyMemberDomains` (domain-restricted sharing) | Refuses IAM members from other domains: the `principalSet://` pool members in `wif` mode, and users Britive grants roles to when Britive and Google domains differ | Allow the domains involved, or grant an exception on the project and scope |
| `iam.workloadIdentityPoolProviders` | Restricts which OIDC issuers a pool may trust | Add `https://<tenant>/api/auth/sso/oauth2` |

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars        # then edit: organization_id, project_id, britive_tenant_url
# key mode only:
cp ../google-workspace/terraform.tfvars.example ../google-workspace/terraform.tfvars

# optional, to create the Britive application too
export BRITIVE_TENANT=https://your-tenant.britive-app.com
export BRITIVE_TOKEN=<API token>

./deploy.sh
```

`deploy.sh` signs you in to Google if Application Default Credentials are missing. It then:

1. Applies this directory.
2. Key mode only: prints the client ID and scopes for domain-wide delegation, waits for you to save them in the Google Admin console, and applies `../google-workspace`. It retries the plan for up to 10 minutes while delegation takes effect, then asks before applying.
3. Applies `britive-app/` if `BRITIVE_TENANT` and `BRITIVE_TOKEN` are set. Otherwise it prints the values to enter in the Britive console.

Then, in the Britive console: open the application, select **Save and Test**, then **Scan**. Profiles can only be associated with the folders and projects the scan discovers.

Running by hand is the same steps: `terraform init && terraform apply` here, then in `../google-workspace` (key mode), then in `britive-app/`.

## Values for the Britive console

If you create the application in the console instead of with `britive-app/`:

```bash
terraform output britive_application_values
```

| Britive field | `wif` output | `key` output |
| --- | --- | --- |
| Organization ID | `organization_id` | `organization_id` |
| Project ID for creating service accounts | `project_id_for_creating_service_accounts` | `project_id_for_creating_service_accounts` |
| Workload identity pool ID | `workload_identity_pool_id` | |
| Workload identity provider ID | `workload_identity_provider_id` | |
| Connected service account email | `service_account_email` | |
| Project number for connected service account | `project_number_for_connected_service_account` | |
| Britive issuer URL (check it matches the application's Settings) | `britive_issuer_url` | |
| Service account credentials | | contents of `keys/key.json` |
| G Suite admin (*Custom user email* in current tenants), Customer ID | | `terraform -chdir=../google-workspace output` |
| Scan all folders and projects / Scan projects only | | one must be selected; `britive-app/` picks from `access_scope` |

The application's display name may contain only letters, digits and spaces; the tenant rejects other characters. When your Britive users and Google identities use different email domains, set **Replace domain** with the Britive domain as primary and the Google domain as secondary (`britive_users_domain` and `google_domain` in `britive-app/`).

## Access scope

`access_scope = "organization"` (default) lets Britive grant roles anywhere in the organisation. `"folder"` or `"project"` with `scope_id` grants the role only there. The role itself is always an organisation custom role, so it can be granted at any level. The organisation and folder permissions it contains have no effect when it is granted on a project.

## Upgrading from the previous version

The previous version named everything after `common_resource_name` (default `BritiveIntegration`) and always used a key. `moved.tf` maps the old resource addresses, so the objects are kept. To keep their names too, set these in `terraform.tfvars`:

```hcl
integration_type   = "key"
project_id         = "britiveintegration"
role_id            = "BritiveIntegration"
service_account_id = "britiveintegration"
```

In `../google-workspace/terraform.tfvars`, set `admin_role_name = "BritiveIntegration"` and `admin_user_name = "britiveintegration"`.

The old role grant was authoritative: destroying it removes every member of the role, including the grant that replaces it. Forget it before the first apply, so the new grant takes over without a gap:

```bash
terraform state rm google_organization_iam_binding.organization
```

Then run `terraform plan` in each directory. One replacement is expected: the key file moves from `terraform/keys/key.json` to `keys/key.json` here, so `local_sensitive_file.key` is recreated (the key itself is unchanged). Delete the old `terraform/keys/key.json` by hand afterwards; it is not ignored at that path. If the previous version was applied from the `gcp/` and `workspace/` subdirectories, copy those state files to this directory and `../google-workspace` first. To move to `wif` afterwards, switch `integration_type`, apply, create a `GCP WIF` application, and delete the old application and key.

`moved.tf` in this directory and in `../google-workspace` exists for that upgrade only; remove both files once every deployment has been applied on this version.

## Remove

```bash
./destroy.sh
```

This removes the Britive application, then the Workspace role and user (key mode), then the Google Cloud resources.

- **Project protection.** The project has `deletion_policy = PREVENT` unless `allow_project_deletion = true`: deleting it would delete the service account and break the integration. To delete it, set the variable and run `terraform apply` first. Deleted projects can be restored for 30 days.
- **Reserved IDs.** A deleted organisation custom role keeps its ID reserved for several weeks, and a deleted workload identity pool for 30 days. To re-create the integration soon after removing it, choose new `role_id` and `workload_identity_pool_id` values.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `API ... has not been used in project ... or it is disabled` on the first apply | The APIs were just enabled | Apply again; the module already waits 60 seconds |
| `already exists` on `google_project` | Project IDs are unique across all of Google Cloud | Choose another `project_id`, or `create_project = false` for one you own |
| `already exists` or `deleted` on the custom role or the pool | The ID is still reserved after a destroy | New `role_id` / `workload_identity_pool_id` |
| `Key creation is not allowed on this service account` | `iam.disableServiceAccountKeyCreation` is enforced | Use `wif`, or an exception on the project |
| `One or more users named in the policy do not belong to a permitted customer` | Domain-restricted sharing | See the organisation policies table above |
| Workspace plan keeps failing with `unauthorized_client` | Delegation not saved, wrong client ID or scopes, or not yet in effect | Compare with what `deploy.sh` printed; changes can take several minutes |
| Britive `Save and Test` fails for a `wif` application | The issuer URL or pool and provider IDs differ from what Britive expects | Compare `britive_issuer_url` with the application's Settings -> Britive Issuer URL; set `britive_issuer_url` if they differ |
| `invalid character found in catalogAppDisplayName` | Punctuation in the application name | Letters, digits and spaces only |
