# Britive - Azure integration with Terraform (workload identity federation)

Sets up everything Microsoft Entra ID and Azure need before Britive can scan an Azure tenant and grant just-in-time access to it, for the Britive **Azure WIF** application type. Britive signs in with workload identity federation: the tenant presents its own OpenID Connect token to Entra ID and receives a token for the app registration created here. No client secret exists anywhere.

Product steps: [Azure WIF onboarding guide](https://docs.britive.com/docs/microsoft-azure-workload-identity-federation-onboarding-guide), [prerequisites](https://docs.britive.com/docs/prerequisites-azure-wif), [onboarding the application](https://docs.britive.com/docs/onboarding-an-azure-wif-application-in-britive-1). For the older **Azure** application type with a client secret, follow [its prerequisites](https://docs.britive.com/docs/prerequisites-azure) in the portal; this directory does not create secrets.

## What gets created

| Resource | Mode | Notes |
| --- | --- | --- |
| App registration **Britive** + service principal | both | Single tenant, public client with redirect URI `https://login.microsoftonline.com/common/oauth2/nativeclient`, as the guide registers it |
| Federated identity credential | both | Issuer `<britive_tenant_url>/api/auth/sso/oauth2`, subject `sys@britive.com`, audience `api://AzureADTokenExchange` |
| Microsoft Graph application permissions, admin-consented | both | `Directory.Read.All`; `AuditLog.Read.All` (`enable_last_sign_in`) |
|  | dynamic | + `Application.ReadWrite.OwnedBy`, `GroupMember.ReadWrite.All`, `RoleManagement.ReadWrite.Directory` |
| Role assignment at the **Tenant Root Group** | discovery | Built-in **Reader** |
|  | dynamic | Custom role **Britive-Integration-Role** (`*/read` + `Microsoft.Authorization/roleAssignments/read|write|delete`), assignable at the root so it covers every subscription and resource group |
|  | `scan_ai_identities` | + **Foundry User**, for Azure AI Foundry agents |

`integration_mode`:

- **discovery** - Britive scans users, groups, directory roles, management groups, subscriptions and resources, and shows existing access. Nothing is granted.
- **dynamic** (default) - Britive also assigns Azure roles and group memberships to users at checkout and removes them at checkin, and creates service principals for programmatic access.

Britive's WIF prerequisites page lists **Reader** for both modes. Reader cannot create role assignments, so dynamic mode here uses the custom role from the [dynamic permissioning page of the Azure guide](https://docs.britive.com/docs/assigning-azure-permissions-for-dynamic-permissioning), which the WIF guide's dynamic section links to. Use `integration_mode = "discovery"` if you only need visibility.

## Before you start

**Tools:** Terraform 1.5 or later, the Azure CLI (`az`).

**Azure rights** for the identity running Terraform (`az login`):

| Needed for | Role |
| --- | --- |
| The app registration, service principal and federated credential | **Application Administrator** (or Global Administrator) |
| Admin consent for the Graph application permissions | **Privileged Role Administrator** (or Global Administrator); Application Administrator alone cannot consent to `RoleManagement.ReadWrite.Directory` |
| Role assignments at the Tenant Root Group | **User Access Administrator** at the root, which a Global Administrator obtains with *Elevate access*: `az rest --method post --url "/providers/Microsoft.Authorization/elevateAccess?api-version=2016-07-01"` |

**A subscription** in the tenant for the `azurerm` provider to initialise against (`subscription_id` or `ARM_SUBSCRIPTION_ID`); nothing is created in it.

**Last sign-in dates** need a Microsoft Entra ID P1 or P2 licence in addition to `AuditLog.Read.All`; without the licence Britive leaves the field empty.

## Deploy

```bash
az login
cp terraform.tfvars.example terraform.tfvars      # britive_tenant_url, integration_mode
terraform init
terraform apply
terraform output britive_application_values
```

Then, in the Britive console, **System Administration → Tenant Applications → Create Application → Azure WIF**:

| Britive field | Terraform output |
| --- | --- |
| Azure Tenant ID | `azure_tenant_id` |
| Azure Application (Client) ID | `azure_application_client_id` |
| Federated Credential Audience | `federated_credential_audience` |
| Britive Issuer URL (shown by Britive; check it equals) | `britive_issuer_url` |
| Login URL | `https://portal.azure.com/` unless you use a custom portal URL |
| Scan AI Identities | tick when `scan_ai_identities = true` |
| Credential Type | Console Access and/or Programmatic Access; programmatic needs `integration_mode = "dynamic"` (Britive creates service principals) |

**Save and Test**, then **Scan**. The Advanced Settings on the same tab choose what the scan covers (management groups and subscriptions, resource groups and resources, service principals, group memberships); the role assignment here allows all of them.

If the Britive Issuer URL shown in the console differs from the `britive_issuer_url` output, set `britive_issuer_url` in `terraform.tfvars` and apply again before testing.

## Remove

`terraform destroy` removes the role assignments, the custom role, the federated credential and the app registration. Remove the Azure WIF application from Britive first. Entra ID keeps a deleted app registration for 30 days; recreating with the same name is fine, but the new registration has a new client ID.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Authorization_RequestDenied: Insufficient privileges` on `azuread_app_role_assignment` | Admin consent needs Privileged Role Administrator or Global Administrator | Run as such a role, or have one grant consent in the portal (**App registrations → Britive → API permissions → Grant admin consent**) and import the assignments |
| `AuthorizationFailed` creating the role definition or assignment at `/providers/Microsoft.Management/managementGroups/<tenant>` | No User Access Administrator at the Tenant Root Group | *Elevate access* as a Global Administrator (command above), then apply again; remove the elevation afterwards |
| `RoleDefinitionDoesNotExist` for `Foundry User` | The built-in role is named differently in your cloud | `az role definition list --query "[?contains(roleName, 'Foundry')].roleName"` and set `ai_identity_role_name` |
| **Save and Test** fails in Britive with a token or `AADSTS70021` / `AADSTS700211` error | Issuer, subject or audience of the federated credential do not match what Britive sends | Compare `britive_issuer_url` with the application's Settings; keep subject `sys@britive.com` and the same audience on both sides |
| Scan lists users but no subscriptions | Role assignment not yet propagated, or **Scan Management Groups and Subscriptions** not selected in Advanced Settings | Wait a few minutes; enable the option and scan again |
| Checkout fails in dynamic mode with a role-assignment error | `integration_mode = "discovery"` (Reader only) | Switch to `dynamic` and apply |
