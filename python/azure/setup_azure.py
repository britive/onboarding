from azure.identity import AzureCliCredential
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.authorization import AuthorizationManagementClient
from azure.graphrbac import GraphRbacManagementClient
from azure.graphrbac.models import ApplicationCreateParameters, PasswordCredential, ServicePrincipalCreateParameters, RequiredResourceAccess, ResourceAccess

# Authenticate using Azure CLI
credential = AzureCliCredential()

# Initialize clients
subscription_id = 'your-subscription-id'
resource_client = ResourceManagementClient(credential, subscription_id)
auth_client = AuthorizationManagementClient(credential, subscription_id)
tenant_id = 'your-tenant-id'
graphrbac_client = GraphRbacManagementClient(credential, tenant_id)

# Define permissions
directory_permissions = [
    {
        "resource_app_id": "00000003-0000-0000-c000-000000000000",  # Microsoft Graph API ID
        "resource_access": [
            ResourceAccess(id="d15c2b5d-df4e-44b4-9638-fb2b3826c1ce", type="Role"),  # Application.ReadWrite.OwnedBy
            ResourceAccess(id="62a82d76-70ea-41e2-9197-370581804d09", type="Role"),  # GroupMember.ReadWrite.All
            ResourceAccess(id="cf1c38e5-3621-4004-a7cb-879624dced7c", type="Role"),  # RoleManagement.ReadWrite.Directory
            ResourceAccess(id="5778995a-e1bf-45b8-affa-663a9f3f4d04", type="Role")   # Directory.Read.All
        ]
    }
]

# Register an application
app_name = 'Britive'
password = 'your-strong-password'
app_params = ApplicationCreateParameters(
    display_name=app_name,
    identifier_uris=[],
    password_credentials=[PasswordCredential(
        start_date=None,
        end_date=None,
        key_id=None,
        value=password
    )],
    required_resource_access=[RequiredResourceAccess(
        resource_app_id=perm["resource_app_id"],
        resource_access=perm["resource_access"]
    ) for perm in directory_permissions]
)
app = graphrbac_client.applications.create(app_params)

# Create a service principal for the application
sp_params = ServicePrincipalCreateParameters(app_id=app.app_id)
sp = graphrbac_client.service_principals.create(sp_params)

# Assign roles to the application
role_definition_id = '/subscriptions/{}/providers/Microsoft.Authorization/roleDefinitions/{}'.format(subscription_id, 'role-definition-id')
scope = '/subscriptions/{}'.format(subscription_id)
role_assignment_params = {
    'role_definition_id': role_definition_id,
    'principal_id': sp.object_id
}
auth_client.role_assignments.create(scope, 'role-assignment-id', role_assignment_params)

# Get client credentials
print('Application ID:', app.app_id)
print('Tenant ID:', tenant_id)
print('Client Secret:', password)
