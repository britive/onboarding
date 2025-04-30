#!/usr/bin/env python3
import time
from googleapiclient import discovery
from google.cloud import iam_credentials_v1
from google.cloud import iam
from google.iam.v1 import policy_pb2 as iam_policy
from google.oauth2 import service_account
import argparse
from googleapiclient.errors import HttpError


# Run the following command to establish cli session with GCP admin account
# gcloud auth application-default login

class BritiveGCP:
    def __init__(self, project_id='britive', service_account_name='britive-service',
                 service_account_display_name='Britive Service', role_id='BritiveIntegrationRole'):
        self.project_id = project_id
        self.role_id = role_id
        self.service_account_name = service_account_name
        self.service_account_display_name = service_account_display_name
        self.credentials = service_account.Credentials.from_service_account_file('google-cloud/service_account_creds.json')
        self.service = discovery.build('iam', 'v1', credentials=self.credentials)
        self.cloudresourcemanager = discovery.build('cloudresourcemanager', 'v1', credentials=self.credentials)

    def create_role(self):
        service_account_email = f'{self.service_account_name}@{self.project_id}.iam.gserviceaccount.com'

        # Step 1: Check if the service account exists
        try:
            self.service.projects().serviceAccounts().get(
                name=f'projects/{self.project_id}/serviceAccounts/{service_account_email}'
            ).execute()
            print(f"Service account '{service_account_email}' already exists.")
        except HttpError as e:
            if e.resp.status == 404:
                # Step 2: Create the service account if it does not exist
                print(f"Creating service account '{service_account_email}'...")
                service_account_body = {
                    'accountId': self.service_account_name,
                    'serviceAccount': {
                        'displayName': self.service_account_display_name
                    }
                }
                self.service.projects().serviceAccounts().create(
                    name=f'projects/{self.project_id}',
                    body=service_account_body
                ).execute()
                print(f"Service account '{service_account_email}' created.")
            else:
                raise

        # Step 3: Define role details
        role_id = self.role_id
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

        # Step 4: Create the custom role
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
            role = self.service.projects().roles().create(
                parent=f'projects/{self.project_id}',
                body=custom_role_body
            ).execute()
            print(f"Custom role created: {role_id}")
        except HttpError as e:
            if e.resp.status == 409:
                print(f"Custom role '{role_id}' already exists.")
            else:
                raise

        # Optional delay to ensure the role is propagated before assignment
        time.sleep(5)

        # Step 5: Get current IAM policy
        policy = self.cloudresourcemanager.projects().getIamPolicy(resource=self.project_id, body={}).execute()

        # Step 6: Add new binding if not already present
        new_binding = {
            'role': f'projects/{self.project_id}/roles/{role_id}',
            'members': [f'serviceAccount:{service_account_email}']
        }

        if not any(
                b['role'] == new_binding['role'] and f'serviceAccount:{service_account_email}' in b.get('members', [])
                for b in policy.get('bindings', [])
        ):
            policy.setdefault('bindings', []).append(new_binding)
            policy_body = {'policy': policy}

            updated_policy = self.cloudresourcemanager.projects().setIamPolicy(
                resource=self.project_id,
                body=policy_body
            ).execute()
            print(f"Role '{role_id}' assigned to service account '{service_account_email}'.")
        else:
            print(f"Service account '{service_account_email}' already has role '{role_id}'.")


def main():
    # Set up argument parser
    parser = argparse.ArgumentParser(description="Create a service account role with specified parameters.")
    parser.add_argument('-p', '--project_id', type=str,
                        default='britive', help="The project ID for the service account.")
    parser.add_argument('-s', '--service_account_name', type=str,
                        default='britive-service', help="The name for the service account.")
    parser.add_argument('-d', '--service_account_display_name', type=str,
                        default='Britive Service', help="The display name for the service account.")
    parser.add_argument('-r', '--role_id', type=str,
                        default='BritiveIntegrationRole', help="Name oft he role to be created for Britive integration.")
    # Parse arguments
    args = parser.parse_args()

    # Create an instance of ServiceAccountRole with provided or default values
    service_account_role = BritiveGCP(
        project_id=args.project_id,
        service_account_name=args.service_account_name,
        service_account_display_name=args.service_account_display_name,
        role_id=args.role_id
    )

    # Call create_role method
    service_account_role.create_role()


if __name__ == '__main__':
    main()
