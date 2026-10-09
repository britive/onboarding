# Google Workspace admin role and user for Britive

Used by two application types, both of which impersonate a Workspace admin user through domain-wide delegation granted to a Britive service account:

- the legacy, key-based **GCP** application (`integration_type = "key"` in [../google-cloud](../google-cloud/README.md); the recommended **GCP WIF** application does not use it), and
- the **Google Workspace** application ([../google-workspace-application](../google-workspace-application/README.md)), whose `deploy.sh` runs this root with its own key (`service_account_key_file`).

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

Outputs `gsuite_admin_email` and `workspace_customer_id` are the application's **G Suite admin** (labelled *Custom user email* in current tenants) and **Customer ID**.

**Sign in once.** Britive's [GCDS user prerequisite](https://docs.britive.com/docs/cis-custom-user) asks that the user sign in at least once so Workspace's terms are accepted; impersonation can fail for a user who never has. Retrieve the generated password with `terraform output -raw initial_password`, sign in as `gsuite_admin_email` in a private window, accept the terms, and sign out. Nobody needs the password afterwards.

**Scopes.** Britive documents four delegation scopes for the GCP application (`admin.directory.user`, `cloud-platform`, `admin.directory.group`, `admin.directory.group.member`). The fifth scope `deploy.sh` prints, `admin.directory.rolemanagement`, exists only so this module can create the admin role *through Britive's own service account*; it stays on that account's delegation entry — and so on the key Britive holds — until you remove it. After a successful apply, edit the delegation entry in the Admin console and drop that scope; re-add it before running `terraform destroy`. Alternatively create the role and user by hand with an administrator credential and skip this module.

The `hashicorp/googleworkspace` provider was archived by HashiCorp on 30 June 2025. It still works and is pinned to its last release, 0.7.0, but receives no fixes. Another reason to prefer the WIF application.
