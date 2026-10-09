# The Azure side of the Britive "Azure WIF" application: an app registration
# the Britive tenant signs in to with workload identity federation (no client
# secret), the Microsoft Graph permissions Britive scans the directory with,
# and the role assignment at the Tenant Root Group that lets Britive see
# management groups and subscriptions and, in dynamic mode, grant roles.
#
# Matches docs.britive.com/docs/registering-britive-application-in-microsoft-entra-id,
# configuring-federated-credentials, assign-directory-permissions-discovery-visibility,
# assigning-directory-permissions-for-dynamic-permissioning,
# assigning-azure-permissions-discovery-visibility and
# assigning-azure-permissions-for-dynamic-permissioning.

data "azuread_client_config" "current" {}

# Microsoft Graph's service principal: the application permissions are its
# app roles, looked up by name so no GUIDs are hard-coded.
data "azuread_service_principal" "msgraph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

locals {
  tenant_id = data.azuread_client_config.current.tenant_id
  dynamic   = var.integration_mode == "dynamic"

  # The Tenant Root Group's ID is the tenant ID.
  root_management_group = "/providers/Microsoft.Management/managementGroups/${local.tenant_id}"

  issuer_url = coalesce(var.britive_issuer_url, "${var.britive_tenant_url}/api/auth/sso/oauth2")

  # Graph application permissions. Discovery reads the directory; dynamic
  # permissioning also manages group memberships, directory roles and the
  # service principals Britive creates for programmatic access.
  graph_permissions = concat(
    ["Directory.Read.All"],
    var.enable_last_sign_in ? ["AuditLog.Read.All"] : [],
    local.dynamic ? ["Application.ReadWrite.OwnedBy", "GroupMember.ReadWrite.All", "RoleManagement.ReadWrite.Directory"] : [],
  )
}

# ------------------------------------------------------------ app registration
resource "azuread_application" "britive" {
  display_name     = var.application_name
  sign_in_audience = "AzureADMyOrg"

  # Britive's guide registers a public client with this redirect URI.
  public_client {
    redirect_uris = ["https://login.microsoftonline.com/common/oauth2/nativeclient"]
  }

  required_resource_access {
    resource_app_id = data.azuread_service_principal.msgraph.client_id

    dynamic "resource_access" {
      for_each = toset(local.graph_permissions)
      content {
        id   = data.azuread_service_principal.msgraph.app_role_ids[resource_access.value]
        type = "Role"
      }
    }
  }
}

resource "azuread_service_principal" "britive" {
  client_id = azuread_application.britive.client_id
}

# Admin consent for the application permissions above.
resource "azuread_app_role_assignment" "graph" {
  for_each = toset(local.graph_permissions)

  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value]
  principal_object_id = azuread_service_principal.britive.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

# The Britive tenant exchanges its own OIDC token for an Entra token for this
# application. Issuer, subject and audience must match what the Britive
# application shows under Settings.
resource "azuread_application_federated_identity_credential" "britive" {
  application_id = azuread_application.britive.id
  display_name   = "britive-tenant"
  description    = "Tokens issued by the Britive tenant"
  issuer         = local.issuer_url
  subject        = var.federated_credential_subject
  audiences      = [var.federated_credential_audience]
}

# ---------------------------------------------- Azure RBAC at the Tenant Root Group
# Discovery: read management groups, subscriptions, resource groups and
# resources.
resource "azurerm_role_assignment" "reader" {
  count = local.dynamic ? 0 : 1

  scope                = local.root_management_group
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.britive.object_id
  principal_type       = "ServicePrincipal"
}

# Dynamic permissioning: the same reads, plus creating and deleting the role
# assignments Britive makes at checkout and removes at checkin. Assignable at
# the root so it covers every subscription and resource group.
resource "azurerm_role_definition" "britive" {
  count = local.dynamic ? 1 : 0

  name        = var.custom_role_name
  scope       = local.root_management_group
  description = "Britive: read everything, manage role assignments"

  permissions {
    actions = [
      "*/read",
      "Microsoft.Authorization/roleAssignments/read",
      "Microsoft.Authorization/roleAssignments/write",
      "Microsoft.Authorization/roleAssignments/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [local.root_management_group]
}

resource "azurerm_role_assignment" "britive" {
  count = local.dynamic ? 1 : 0

  scope              = local.root_management_group
  role_definition_id = azurerm_role_definition.britive[0].role_definition_resource_id
  principal_id       = azuread_service_principal.britive.object_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "ai_identities" {
  count = var.scan_ai_identities ? 1 : 0

  scope                = local.root_management_group
  role_definition_name = var.ai_identity_role_name
  principal_id         = azuread_service_principal.britive.object_id
  principal_type       = "ServicePrincipal"
}
