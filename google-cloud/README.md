# Britive - Google Onboarding via Terraform

This process is broken down into 2 primary steps.

1. Create the required resources in GCP
2. Create the required resources in Google Workspace

Step 2 requires Domain Wide Delegation so that has to be performed manually before we can apply the Workspaces Terraform template.


## Deploying

### Step 1

Modify `variables.tfvars` to set up the required inputs.

* organization_id - the ID of the GCP Organization
* common_resource_name - what to name the resources which are created - generally "BritiveIntegration" is fine
* workspace_customer_id - the Google Workspaces customer ID
* workspace_domain = the Google Workspaces domain
* workspace_impersonation_email - the email address of the Google Workspace user to impersonate when we deploy the required Workspaces resources (a limited set of scopes will be used)


## Step 2

Run the deployment script. Your browser will open and ask you to authenticate, so we can obtain
GCP credentials. Authenticate as an admin user.

~~~
./deploy.sh
~~~