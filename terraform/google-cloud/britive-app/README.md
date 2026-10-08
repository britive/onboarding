# Britive application for Google Cloud

Creates the Britive application from what [the google-cloud module](../README.md) set up: a **GCP WIF** application for `integration_type = "wif"`, or a **GCP** application for `"key"` (which also reads the Google Workspace values from [../../google-workspace](../../google-workspace/README.md)). It reads `../terraform.tfstate`, so nothing is copied by hand.

```bash
export BRITIVE_TENANT=https://your-tenant.britive-app.com
export BRITIVE_TOKEN=<API token with rights over Applications>
cp terraform.tfvars.example terraform.tfvars   # optional: name, domain mapping
terraform init
terraform apply
```

Then open the application in the Britive console, select **Save and Test**, then **Scan**. Create profiles once the scan has finished.

| Variable | Default | Meaning |
| --- | --- | --- |
| `application_name` | `Google Cloud` | Display name. Letters, digits and spaces only |
| `britive_users_domain`, `google_domain` | none | Set both when Britive users and Google identities use different email domains; Britive then grants roles to `<user>@<google_domain>` |
| `programmatic_access` | `false` | Also issue temporary service account keys at checkout. Needs key creation allowed by organisation policy |
| `max_session_duration_seconds` | `43200` | Longest checkout any profile may grant |
| `gsuite_admin_email`, `workspace_customer_id` | from `../../google-workspace` | Key mode only, when that module was not applied with Terraform |

Console access is always on. Single sign-on to Google from Britive is off; configure it separately if you use Britive as your Google identity provider.
