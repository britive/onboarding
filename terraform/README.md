# Britive - Terraform examples

| Directory | What it sets up |
| --- | --- |
| [aws](aws/README.md) | AWS integration: one module, used by single-account, organization (StackSet) and lab stacks |
| [azure](azure/README.md) | Azure integration for the Azure WIF application: app registration with a federated credential (no secret), Graph permissions, role assignment at the Tenant Root Group |
| [britive](britive/README.md) | Britive side with the Britive provider: tags, profiles, permissions and policies on an AWS application |
| [google-cloud](google-cloud/README.md) | Google Cloud integration: workload identity federation (recommended) or a service account key, and optionally the Britive application |
| [google-workspace](google-workspace/README.md) | Google Workspace admin user for the key-based Google Cloud application only (not the Google Workspace application type) |
| [snowflake](snowflake/README.md) | Snowflake role and service user for the Snowflake / Snowflake Standalone applications |

Prerequisites and the product side of each integration are documented at
<https://docs.britive.com/docs/application-onboarding-guides>; every README
here links the stack's outputs to the Britive application fields.
