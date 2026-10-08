# Google Workspace for the Britive GCP application (key mode)

Only for the legacy, key-based Britive **GCP** application (`integration_type = "key"` in [../google-cloud](../google-cloud/README.md)). The recommended **GCP WIF** application does not use it.

Creates a Workspace admin role limited to reading organisational units, users and groups and updating groups, and a Workspace user `britive-integration@<domain>` holding it. Britive acts as that user, the application's **G Suite admin**, through domain-wide delegation granted to the Britive service account. The user takes a Workspace licence. Its password is random and kept only in Terraform state: nobody signs in as it.

`../google-cloud/deploy.sh` runs this module for you after you grant delegation. To run it by hand:

1. In the Google Admin console (Security -> Access and data control -> API controls -> Manage Domain Wide Delegation), add the client ID from `terraform -chdir=../google-cloud output -raw service_account_client_id` with these scopes:

   ```
   https://www.googleapis.com/auth/admin.directory.user,https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/admin.directory.group,https://www.googleapis.com/auth/admin.directory.group.member,https://www.googleapis.com/auth/admin.directory.rolemanagement
   ```

2. Apply:

   ```bash
   cp terraform.tfvars.example terraform.tfvars   # customer ID, domain, a super administrator to act as
   terraform init
   terraform apply                                 # retry if it fails with unauthorized_client: delegation can take minutes
   ```

Outputs `gsuite_admin_email` and `workspace_customer_id` are the application's **G Suite admin** and **Customer ID**.

The `hashicorp/googleworkspace` provider was archived by HashiCorp on 30 June 2025. It still works and is pinned to its last release, 0.7.0, but receives no fixes. Another reason to prefer the WIF application.
