# Britive application for Google Workspace

Creates the **Google Workspace** application in Britive from what [the google-workspace-application root](../README.md) (service account and key) and [../../google-workspace](../../google-workspace/README.md) (the admin user Britive acts as) set up. It reads both roots' state, so nothing is copied by hand.

```bash
export BRITIVE_TENANT=https://your-tenant.britive-app.com
export BRITIVE_TOKEN=<API token with rights over Applications>
cp terraform.tfvars.example terraform.tfvars   # optional
terraform init
terraform apply
```

Then open the application in the Britive console, select **Save and Test**, then **Scan**. Create profiles once the scan has finished.

| Britive field | Variable | Default |
| --- | --- | --- |
| Google Workspace Admin Email | `gsuite_admin_email` | from `../../google-workspace` |
| Service Account Credentials (JSON) | — | the key from `../` |
| Login URL | `login_url` | `https://admin.google.com` |
| Create user account for super admin role | `create_user_for_super_admin` | `false` |
| Scan Roles / Scan Groups | `scan_roles`, `scan_groups` | `true` / `true` |
| Enable SSO, Audience, ACS URL | `enable_sso` (Google's standard values for the domain) | `false` |
| Use another domain for account mapping | `britive_users_domain` (+ `google_domain`) | off |
| Profile Settings: maximum session duration | `max_session_duration_seconds` | `43200` |

Account mapping is by **Email**, as the guide selects.
