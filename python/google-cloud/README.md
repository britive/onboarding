
---

# 🔐 Britive GCP & Google Workspace Role Setup

This repository includes automation scripts to configure the required roles and permissions for integrating **Britive** with:

1. **Google Cloud Platform (GCP)** – `setup_gcp.py`
2. **Google Workspace / GCDS** – `setup_gcds.py`

---

## 📄 Scripts Overview

### `setup_gcp.py`

Creates a **custom IAM role** in a GCP project and binds it to a specified **service account**. This role provides the necessary permissions for Britive to manage service accounts and IAM policies.

### `setup_gcds.py`

Creates a **custom Google Workspace Admin SDK role** with specific directory-level privileges required for Britive integration with **Google Cloud Directory Sync (GCDS)**.

---

## ⚙️ Prerequisites

- Python 3.9+
- Google Cloud Project with APIs enabled:
  - IAM API
  - Cloud Resource Manager API
  - Admin SDK API (for Workspace)

### 📦 Install Dependencies

```bash
pip install google-api-python-client google-cloud-iam google-cloud-iam-credentials google-auth google-auth-oauthlib
```

---

## 🔐 Authentication Setup

### 🔸 For `setup_gcp.py`

1. Authenticate using Google CLI:

```bash
gcloud auth application-default login
```

2. Download a **service account key** with the following roles:
   - `IAM Security Admin`
   - `Project IAM Admin`

3. Save the key as:

```
google-cloud/service_account_creds.json
```

---

### 🔹 For `setup_gcds.py`

1. In your [Google Cloud Console](https://console.cloud.google.com/apis/credentials), create an **OAuth 2.0 Client ID** (Desktop app).

2. Download the OAuth credentials JSON file and update:

```python
CREDENTIALS_FILE = 'path/to/credentials.json'
```

---

## 🚀 Usage

### 🔸 Run GCP Role Setup

```bash
python setup_gcp.py
```

Optional args:

```bash
python setup_gcp.py \
  --project_id=my-gcp-project \
  --service_account_name=britive-sa \
  --service_account_display_name="Britive Service Account"
```

✅ Creates a custom IAM role and assigns it to the specified service account.

---

### 🔹 Run GCDS Role Setup

```bash
python setup_gcds.py
```

> Replace the `customer_id` in the script with either:
> - `'my_customer'` (default for primary domain)
> - or your actual Workspace customer ID.

✅ Creates a custom Admin SDK role with:
- `ORG_UNITS_READ`
- `USER_READ`
- `GROUP_READ`
- `GROUP_UPDATE`

---

## ✅ Output Examples

### GCP Script

```
Custom role created: BritiveIntegrationRole
Role 'BritiveIntegrationRole' assigned to service account 'britive-service@your-project.iam.gserviceaccount.com'.
```

### GCDS Script

```json
Custom role created: {
  "roleId": "...",
  "roleName": "BritiveDirectoryRole",
  ...
}
```

---

## 🛡️ Permissions Summary

### GCP Role Permissions

| Permission | Description |
|------------|-------------|
| `iam.*`    | Manage service accounts & keys |
| `resourcemanager.*` | Manage project IAM policies |

### GCDS Role Privileges

| Privilege | Scope |
|-----------|-------|
| `ORG_UNITS_READ` | Read organizational units |
| `USER_READ` | View user directory |
| `GROUP_READ` | View groups |
| `GROUP_UPDATE` | Modify groups |
