# Google Cloud with Python

Two scripts for the **key-based** Google Cloud integrations. For an
organization-level application or Workload Identity Federation (keyless),
use [`../../terraform/google-cloud/`](../../terraform/google-cloud/).

| Script | Creates | Britive application |
| ------ | ------- | ------------------- |
| `setup_gcp.py` | A service account and the 19-permission *projects only* custom role, bound on one project | **GCP Standalone** — [prerequisites](https://docs.britive.com/docs/creating-a-custom-role-for-gcp-standalone-application) |
| `setup_gcds.py` | The Google Workspace admin role for directory sync (OU/users/groups read, groups update) | **GCP** (organization, key mode) — [GCDS role](https://docs.britive.com/docs/cis-custom-role-gcds) |

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## `setup_gcp.py`

Authenticates with Application Default Credentials
(`gcloud auth application-default login` as someone with
`iam.serviceAccounts.create`, `iam.roles.create` and
`resourcemanager.projects.setIamPolicy` on the project), or with a service
account key via `--credentials`.

```bash
python3 setup_gcp.py --project-id my-project
python3 setup_gcp.py --project-id my-project --service-account-name britive-sa --role-id BritiveIntegrationRole
```

Idempotent: an existing service account is kept, an existing role has its
permissions refreshed, an existing binding is left alone. IAM policy is
read and written at version 3 so conditional bindings survive.

Then create a key and upload it when creating the **GCP Standalone**
application in Britive:

```bash
gcloud iam service-accounts keys create britive-key.json --iam-account britive-service@my-project.iam.gserviceaccount.com
```

Keep the key out of the repository (`*.json` keys are not tracked here).

## `setup_gcds.py`

Needs an OAuth desktop client JSON from the Google Cloud console with the
Admin SDK API enabled; a browser opens for a Workspace super administrator
to consent.

```bash
python3 setup_gcds.py --client-secrets client_secret.json
python3 setup_gcds.py --client-secrets client_secret.json --customer-id C01abcdef --role-name BritiveDirectoryRole
```

The script resolves the privilege IDs from the Admin SDK (`privileges.list`)
rather than hard-coding them, creates the role, and prints it. Assign the
role to the Britive service account's Workspace user afterwards (Admin
console → Account → Admin roles).
