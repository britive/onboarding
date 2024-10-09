#!/usr/bin/env python3
from googleapiclient import discovery
from google.cloud import iam_credentials_v1
from google.cloud import iam
from google.iam.v1 import policy_pb2 as iam_policy
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
        self.credentials = service_account.Credentials.from_service_account_file('google-cloud/service_account_creds.json')
        self.service = discovery.build('iam', 'v1', credentials=self.credentials)
        self.cloudresourcemanager = discovery.build('cloudresourcemanager', 'v1', credentials=self.credentials)

    def create_role(self):
        # Define role details
        role_id = 'BritiveIntegrationRole'
        role_title = 'Britive Integration Role'
        role_description = 'A custom role with admin permissions for Britive platform'
        role_permissions = [
            'iam.roles.get', 'iam.roles.list', 'iam.serviceAccountKeys.create', 'iam.serviceAccountKeys.delete',
            'iam.serviceAccountKeys.get', 'iam.serviceAccountKeys.list', 'iam.serviceAccounts.create',
            'iam.serviceAccounts.delete', 'iam.serviceAccounts.disable', 'iam.serviceAccounts.enable',
            'iam.serviceAccounts.get', 'iam.serviceAccounts.getIamPolicy', 'iam.serviceAccounts.list',
            'iam.serviceAccounts.setIamPolicy', 'iam.serviceAccounts.undelete', 'iam.serviceAccounts.update',
            'resourcemanager.projects.get', 'resourcemanager.projects.getIamPolicy',
            'resourcemanager.projects.setIamPolicy'
        ]

        # Create the custom role
        custom_role_body = {
            'roleId': role_id,
            'role': {
                'title': role_title,
                'description': role_description,
                'includedPermissions': role_permissions,
                'stage': 'GA'
            }
        }

        try:
            role = self.service.projects().roles().create(parent=f'projects/{self.project_id}',
                                                          body=custom_role_body).execute()
            print(f"Custom role created: {role_id}")
        except Exception as e:
            print(f"Role creation failed: {e}")

        # Get the current IAM policy
        policy = self.cloudresourcemanager.projects().getIamPolicy(resource=self.project_id, body={}).execute()

        # Add the new binding to the policy
        binding = {
            'role': f'projects/{self.project_id}/roles/{role_id}',
            'members': [f'serviceAccount:{self.service_account_name}@{self.project_id}.iam.gserviceaccount.com']
        }
        policy['bindings'].append(binding)

        # Update the IAM policy with the new binding
        policy_body = {'policy': policy}
        updated_policy = self.cloudresourcemanager.projects().setIamPolicy(resource=self.project_id,
                                                                           body=policy_body).execute()
        print(
            f"Role '{role_id}' assigned to service account '{self.service_account_name}@{self.project_id}.iam.gserviceaccount.com'.")


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


