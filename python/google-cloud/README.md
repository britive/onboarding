# Britive GCP Setup Script

This script automates the creation of a custom IAM role and a service account, and assigns the role to the service account in a specified GCP project.
It is designed for integrating the Britive platform with GCP.


## 🔧 Requirements

- Python 3.10+
- Required packages:
  - `google-api-python-client`
  - `google-auth`
  - `google-cloud-iam`
  - `time`
  - `argparse`

Install dependencies:

```bash
pip install -r requirements.txt
```

## 🔐 Authentication

You must authenticate using a GCP service account key with sufficient permissions to:

- Create service accounts
- Create custom roles
- Assign IAM policies

Authenticate via:

```bash
gcloud auth application-default login
```

Create a service account key (if you haven't already):

```bash
gcloud iam service-accounts keys create service_account_creds.json \
  --iam-account your-sa@your-project.iam.gserviceaccount.com
```

Save the key at:

```
google-cloud/service_account_creds.json
```

## 🚀 Usage

Run the script:

```bash
python setup_gcp.py \
  --project_id your-project-id \
  --role_id BritiveIntegrationRole \
  --service_account_name sa-britive-service \
  --service_account_display_name "Britive Service Account"
```


## 📋 What It Does

1. **Checks if the service account exists.** Creates it if it doesn't.
2. **Creates a custom role** named `BritiveIntegrationRole` with GCP IAM permissions required for Britive integration.
3. **Assigns the role** to the service account at the project level.

## 🗂 Directory Structure

```
.
├── setup_gcp.py
├── google-cloud/
│   └── service_account_creds.json
└── README.md
```

## 🛡️ Notes

- The script is **idempotent** — it will skip creation steps for existing resources.
- Custom role propagation may take a few seconds; the script includes a short delay before policy binding.
- Ensure your service account key has permissions like:
  - `iam.roles.create`
  - `iam.serviceAccounts.*`
  - `resourcemanager.projects.setIamPolicy`
