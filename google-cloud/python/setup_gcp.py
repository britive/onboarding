#!/usr/bin/env python3
from google.cloud import iam_v2
from google.oauth2 import service_account

# Run the following command to establish cli session with GCP admin account
# gcloud auth application-default login

# Replace these variables with your details
project_id = 'britive'
service_account_name = 'britive-service'
service_account_display_name = 'Britive Service'

role_id = 'BritiveIntegrationRole'
role_title = 'Britive Integration Role'
role_description = 'A custom role with admin permissions for Britive platform'
role_permissions = ['iam.roles.get', 'iam.roles.list', 'iam.serviceAccountKeys.create', 'iam.serviceAccountKeys.delete',
                    'iam.serviceAccountKeys.get', 'iam.serviceAccountKeys.list', 'iam.serviceAccounts.create',
                    'iam.serviceAccounts.delete', 'iam.serviceAccounts.disable', 'iam.serviceAccounts.enable',
                    'iam.serviceAccounts.get', 'iam.serviceAccounts.getIamPolicy', 'iam.serviceAccounts.list',
                    'iam.serviceAccounts.setIamPolicy', 'iam.serviceAccounts.undelete', 'iam.serviceAccounts.update',
                    'orgpolicy.policy.get', 'resourcemanager.folders.get', 'resourcemanager.folders.getIamPolicy',
                    'resourcemanager.folders.list', 'resourcemanager.folders.setIamPolicy',
                    'resourcemanager.organizations.get', 'resourcemanager.organizations.getIamPolicy',
                    'resourcemanager.organizations.setIamPolicy', 'resourcemanager.projects.get',
                    'resourcemanager.projects.getIamPolicy', 'resourcemanager.projects.list',
                    'resourcemanager.projects.setIamPolicy', 'bigquery.datasets.update', 'bigquery.tables.get',
                    'bigquery.tables.getIamPolicy', 'bigquery.tables.setIamPolicy', 'apigee.environments.get',
                    'apigee.environments.getIamPolicy', 'apigee.environments.setIamPolicy']

# Initialize the IAM client
credentials = service_account.Credentials.from_service_account_file('./britive-service-account-key.json')
client = iam_v2.IAMClient(credentials=credentials)

# The service account's resource name
resource_name = f'projects/{project_id}'

# Create the service account
service_account = client.create_service_account(
    request={
        'name': resource_name,
        'account_id': service_account_name,
        'service_account': {
            'display_name': service_account_display_name
        }
    }
)
# Define the custom role
role = iam_v2.Role(
    title=role_title,
    description=role_description,
    included_permissions=role_permissions,
    stage=iam_v2.Role.Stage.GA
)

# Create the custom role
created_role = client.create_role(
    request={
        'parent': resource_name,
        'role_id': role_id,
        'role': role
    }
)

print(f'Service account {service_account.email} created.')
print(f'Custom role {created_role.name} created.')

policy = client.get_iam_policy(request={"resource": resource_name})
binding = iam_v2.Binding(
    role=role,
    members=[f'serviceAccount:{service_account.email}']
)
policy.bindings.append(binding)

# Set the new policy
updated_policy = client.set_iam_policy(request={"resource": resource_name, "policy": policy})

print(f'Service account {service_account.email} assigned to role {role}.')
