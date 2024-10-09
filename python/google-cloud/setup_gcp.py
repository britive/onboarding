#!/usr/bin/env python3
from google.cloud import iam_admin_v1
from google.oauth2 import service_account
import argparse


# Run the following command to establish cli session with GCP admin account
# gcloud auth application-default login

class BritiveGCP:
    def __init__(self, project_id='britive', service_account_name='britive-service',
                 service_account_display_name='Britive Service'):
        self.project_id = project_id
        self.service_account_name = service_account_name
        self.service_account_display_name = service_account_display_name

    def create_role(self):
        role_id: str = 'BritiveIntegrationRole'
        role_title: str = 'Britive Integration Role'
        role_description: str = 'A custom role with admin permissions for Britive platform'
        role_permissions = ['iam.roles.get', 'iam.roles.list', 'iam.serviceAccountKeys.create',
                            'iam.serviceAccountKeys.delete',
                            'iam.serviceAccountKeys.get', 'iam.serviceAccountKeys.list', 'iam.serviceAccounts.create',
                            'iam.serviceAccounts.delete', 'iam.serviceAccounts.disable', 'iam.serviceAccounts.enable',
                            'iam.serviceAccounts.get', 'iam.serviceAccounts.getIamPolicy', 'iam.serviceAccounts.list',
                            'iam.serviceAccounts.setIamPolicy', 'iam.serviceAccounts.undelete',
                            'iam.serviceAccounts.update',
                            'orgpolicy.policy.get', 'resourcemanager.folders.get',
                            'resourcemanager.folders.getIamPolicy',
                            'resourcemanager.folders.list', 'resourcemanager.folders.setIamPolicy',
                            'resourcemanager.organizations.get', 'resourcemanager.organizations.getIamPolicy',
                            'resourcemanager.organizations.setIamPolicy', 'resourcemanager.projects.get',
                            'resourcemanager.projects.getIamPolicy', 'resourcemanager.projects.list',
                            'resourcemanager.projects.setIamPolicy', 'bigquery.datasets.update', 'bigquery.tables.get',
                            'bigquery.tables.getIamPolicy', 'bigquery.tables.setIamPolicy', 'apigee.environments.get',
                            'apigee.environments.getIamPolicy', 'apigee.environments.setIamPolicy']

        print(f'Creating role with id {role_id} and description {role_description}.')

        # Initialize the IAM client
        credentials = self.service_account_name.Credentials.from_service_account_file(
            './britive-service-account-key.json')
        client = iam_admin_v1.IAMClient(credentials=credentials)

        # The service account's resource name
        resource_name = f'projects/{self.project_id}'

        # Create the service account
        service_account = client.create_service_account(
            request={
                'name': resource_name,
                'account_id': self.service_account_name,
                'service_account': {
                    'display_name': self.service_account_display_name
                }
            }
        )
        # Define the custom role
        role = iam_admin_v1.Role(
            title=role_title,
            description=role_description,
            included_permissions=role_permissions,
            stage=iam_admin_v1.Role.Stage.GA
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
        binding = iam_admin_v1.Binding(
            role=role,
            members=[f'serviceAccount:{service_account.email}']
        )
        policy.bindings.append(binding)

        # Set the new policy
        updated_policy = client.set_iam_policy(request={"resource": resource_name, "policy": policy})
        print(f'Service account {service_account.email} assigned to role {role}.')


def main():
    # Set up argument parser
    parser = argparse.ArgumentParser(description="Create a service account role with specified parameters.")
    parser.add_argument('-p', '--project_id', type=str,
                        default='britive', help="The project ID for the service account.")
    parser.add_argument('-s', '--service_account_name', type=str,
                        default='britive-service', help="The name for the service account.")
    parser.add_argument('-d', '--service_account_display_name', type=str,
                        default='Britive Service', help="The display name for the service account.")

    # Parse arguments
    args = parser.parse_args()

    # Create an instance of ServiceAccountRole with provided or default values
    service_account_role = BritiveGCP(
        project_id=args.project_id,
        service_account_name=args.service_account_name,
        service_account_display_name=args.service_account_display_name
    )

    # Call create_role method
    service_account_role.create_role()


if __name__ == '__main__':
    main()


