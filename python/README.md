# Python scripts

Scripts that use the [`britive`](https://pypi.org/project/britive/) SDK and
cloud SDKs to do the repetitive part of onboarding. Each directory is
self-contained: its own `requirements.txt`, `README.md` and `.env.example`.

| Directory | What it does | Pairs with |
| --------- | ------------ | ---------- |
| [`aws/`](aws/) | Creates the SAML provider and integration role for Britive in an AWS account with `boto3` (the scripted alternative to the CloudFormation/Terraform templates) | [AWS onboarding guide](https://docs.britive.com/docs/application-onboarding-guides) |
| [`britive/`](britive/) | Bootstraps a tenant from a YAML file: identity providers, users, tags, applications, profiles, notification mediums, broker pools, resource types | any new tenant / POC |
| [`google-cloud/`](google-cloud/) | Creates the service account and the *projects-only* custom role for a GCP Standalone application; creates the GCDS admin role in Google Workspace | GCP Standalone / GCP key mode (Terraform in [`../terraform/google-cloud/`](../terraform/google-cloud/) covers the organization and WIF variants) |
| [`gws_scim/`](gws_scim/) | Simulates SCIM for Google Workspace: diffs a Britive application scan against the tenant and creates/disables users and tag memberships | Google Workspace application |
| [`oci/`](oci/) | `setup_oci.py`: service user, group, API key and policy for the **OCI** application. `setup_oci_wif.py`: service user, group, identity propagation trust and policy in an identity domain for the **OCI WIF** application (no API key) | OCI 2.0 / OCI WIF onboarding guides |
| [`azure/`](azure/) | README only — the previous script targeted the retired Azure AD Graph API and was removed | Azure onboarding guide |

## Conventions

- Credentials come from environment variables (`BRITIVE_TENANT`,
  `BRITIVE_API_TOKEN`, cloud SDK defaults) or an ignored `.env` next to the
  script. Nothing is read from a file in the repository.
- Every script takes `--help`; dry-run flags never call a write API.
- Python 3.10+; `pip install -r requirements.txt` inside each directory.

```bash
cd python/aws
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env     # then edit
python3 setup_aws.py --help
```
