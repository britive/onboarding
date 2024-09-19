import argparse
import os

from azure.identity import DefaultAzureCredential
from azure.core.credentials import TokenCredential
from azure.graphrbac import GraphRbacManagementClient
from azure.graphrbac.models import ApplicationCreateParameters, PasswordCredential
from azure.mgmt.authorization import AuthorizationManagementClient
from azure.mgmt.authorization.models import RoleDefinition, Permission


class AzureBritiveIntegration:
    def __init__(self, subscription_id: str, tenant_id: str):
        # Initialize the credentials and required clients
        self.credential = DefaultAzureCredential()
        assert isinstance(self.credential, TokenCredential)
        self.subscription_id = subscription_id
        self.tenant_id = tenant_id
        self.app_name = "Britive"
        self.role_name = "Britive-Integration-Role"

        # Initialize Graph Rbac Client for AAD operations
        self.graph_client = GraphRbacManagementClient(self.credential, self.tenant_id)

        # Initialize Authorization client for IAM role assignment
        self.auth_client = AuthorizationManagementClient(self.credential, self.subscription_id)

    def register_britive_app(self):
        """
        Registers the Britive app in Azure Active Directory.
        """
        # Step 1: Register the Britive application
        app_parameters = ApplicationCreateParameters(
            display_name=self.app_name,
            identifier_uris=[],
            sign_in_audience="AzureADMyOrg",  # Single tenant
            reply_urls=["https://login.microsoftonline.com/common/oauth2/nativeclient"]
        )

        application = self.graph_client.applications.create(app_parameters)

        # Step 2: Capture the Application (Client) ID and Directory (tenant) ID
        app_id = application.app_id
        tenant_id = self.tenant_id

        print(f"Application (Client) ID: {app_id}")
        print(f"Directory (Tenant) ID: {tenant_id}")

        # Step 3: Create Client Secret
        password_credential = PasswordCredential(
            display_name="BritiveSecret"
        )

        client_secret = self.graph_client.applications.create_password_credential(application.object_id,
                                                                                  password_credential)

        print(f"Client Secret: {client_secret.secret_text}")
        print("Make sure to store this value securely.")

        return app_id, tenant_id, client_secret.secret_text

    def assign_permissions(self):
        """
        Assigns custom role and permissions at the Tenant Root Group level.
        """
        # Step 1: Create Custom Role Definition
        custom_role_properties = RoleDefinition(
            role_name=self.role_name,
            description="Custom role for Britive integration",
            permissions=[Permission(
                actions=["*/read", "Microsoft.Authorization/roleAssignments/*"],
                not_actions=[]
            )],
            assignable_scopes=[f"/subscriptions/{self.subscription_id}"]  # Add all subscriptions or specific ones
        )

        # Step 2: Create the custom role definition
        role_definition = self.auth_client.role_definitions.create_or_update(
            scope=f"/subscriptions/{self.subscription_id}",
            role_definition_id=self.role_name,
            role_definition=RoleDefinition(properties=custom_role_properties)
        )

        print(f"Custom role '{self.role_name}' created with ID: {role_definition.id}")

        # Step 3: Assign the role to the Britive app
        assignments_scope = f"/subscriptions/{self.subscription_id}/providers/Microsoft.Authorization"
        role_assignment = self.auth_client.role_assignments.create(
            scope=assignments_scope,
            role_assignment_name=role_definition.id,
            parameters={
                'role_definition_id': role_definition.id,
                'principal_id': self.graph_client.applications.get(self.tenant_id).object_id
            }
        )
        print(f"Role '{self.role_name}' assigned to Britive application.")
        return role_assignment

    def assign_directory_permissions(self):
        """
        Assign directory permissions for the Britive application.
        """
        # Retrieve the application object
        application = self.graph_client.applications.list(filter=f"displayName eq '{self.app_name}'").next()

        # Define the permissions to be added
        required_permissions = [
            {
                "resourceAppId": "00000003-0000-0000-c000-000000000000",  # Microsoft Graph
                "resourceAccess": [
                    {"id": "df021288-bdef-4463-88db-98f22de89214", "type": "Role"},  # Application.ReadWrite.OwnedBy
                    {"id": "62a82d76-70ea-41e2-9197-370581804d09", "type": "Role"},  # GroupMember.ReadWrite.All
                    {"id": "0285c3f6-10d6-48b4-bc57-4593d2ed26c0", "type": "Role"},
                    # RoleManagement.ReadWrite.Directory
                    {"id": "7ab1d382-f21e-4acd-a863-ba3e13f7da61", "type": "Role"}  # Directory.Read.All
                ]
            }
        ]

        # Assign API permissions
        self.graph_client.applications.patch(
            application_object_id=application.object_id,
            required_resource_access=required_permissions
        )

        print(f"Permissions added to the application '{self.app_name}'.")

        # Grant admin consent for the application
        self.graph_client.applications.grant_admin_consent(application.object_id)

        print(f"Admin consent granted for the application '{self.app_name}'.")


if __name__ == "__main__":
    # Define arguments and usage
    parser = argparse.ArgumentParser(description='Process some command-line arguments.')
    parser.add_argument('-a', '--app', action='store_true',
                        help='Create Britive Application in Azure', default=True)
    parser.add_argument('-r', '--role', action='store_true',
                        help='Create Britive Integration Role', default=True)
    args = parser.parse_args()

    # Instantiate the class
    azure_britive = AzureBritiveIntegration(subscription_id=os.getenv('YOUR_SUBSCRIPTION_ID'),
                                            tenant_id=os.getenv('YOUR_TENANT_ID'))

    if args.app:
        azure_britive.register_britive_app()
    if args.role:
        azure_britive.assign_permissions()
        azure_britive.assign_directory_permissions()
