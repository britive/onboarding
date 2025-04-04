---

# Britive GCP & Workspace Role Setup Scripts

This repository contains two Python scripts designed to automate role and permission setup required for **Britive** integration with Google Cloud Platform (GCP) and Google Workspace (Admin SDK).


## 🛠 Prerequisites

- **Python 3.6+**
- Enable the following Google APIs:
  - [IAM API](https://console.cloud.google.com/apis/library/iam.googleapis.com)
  - [Cloud Resource Manager API](https://console.cloud.google.com/apis/library/cloudresourcemanager.googleapis.com)
  - [Admin SDK API](https://console.cloud.google.com/apis/library/admin.googleapis.com)

### Install Python Dependencies

```bash
pip install google-api-python-client google-cloud-iam google-cloud-iam-credentials google-auth google-auth-oauthlib
```

---

## 🔐 Authentication Setup

### For GCP Script (`create_britive_role.py`)

1. **Enable Application Default Credentials:**

```bash
gcloud auth application-default login
```

2. **Service Account Key File:**

Place the service account key at:

```
google-cloud/service_account_creds.json
```

Ensure the service account has:
- `roles/iam.securityAdmin`
- `roles/resourcemanager.projectIamAdmin`

---

### For Workspace Script (`create_workspace_role.py`)

1. **Create OAuth 2.0 Client ID**:
   - Go to [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials)
   - Choose "OAuth 2.0 Client IDs" and download the JSON file.

2. **Replace** the file path in the script:

```python
CREDENTIALS_FILE = 'path/to/credentials.json'
```

3. When you run the script, a browser window will open to authorize access.

---

## 🚀 Usage

### 1. GCP Role Setup

```bash
python create_britive_role.py
```

With custom args:

```bash
python create_britive_role.py \
  --project_id=my-gcp-project \
  --service_account_name=my-britive-sa \
  --service_account_display_name="My Britive Service Account"
```

This will:
- Create a custom role `BritiveIntegrationRole` with permissions for IAM and project policies.
- Bind the role to the specified service account.

### 2. Workspace Role Setup

```bash
python create_workspace_role.py
```

This will:
- Authenticate via OAuth
- Create a role in the Admin SDK named `BritiveDirectoryRole`
- Assign the following privileges:
  - `ORG_UNITS_READ`
  - `USER_READ`
  - `GROUP_READ`
  - `GROUP_UPDATE`

> 💡 Set `customer_id = 'my_customer'` or use your actual customer ID.

---

## 🔒 Permissions Summary

### GCP Role Permissions

Includes:
- IAM role/service account key creation and management
- Project IAM policy access

### Workspace Role Privileges

Includes:
- Read org units, users, and groups
- Update groups

---

## ✅ Output Example

### GCP Script

```
Custom role created: BritiveIntegrationRole
Role 'BritiveIntegrationRole' assigned to service account 'britive-service@your-project.iam.gserviceaccount.com'.
```

### Workspace Script

```
Custom role created:
{
  "roleId": "...",
  "roleName": "BritiveDirectoryRole",
  ...
}
```

---
