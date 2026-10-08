# Azure

The Python script that used to live here was removed: it depended on
`azure-graphrbac`, which targets the Azure AD Graph API Microsoft retired,
and it assigned the custom role at subscription scope where Britive requires
the Tenant Root Group. It could not run against a current tenant.

Use [`../../terraform/azure/`](../../terraform/azure/) instead: it creates
the app registration with a federated credential (no client secret), the
Microsoft Graph permissions and the role assignment at the Tenant Root Group
for the **Azure WIF** application type.

For the older **Azure** application type with a client secret, follow the
product steps in the portal:

- [Azure prerequisites](https://docs.britive.com/docs/prerequisites-azure)
- [Registering the Britive application in Azure](https://docs.britive.com/docs/registering-britive-application-in-azure)
- Assigning permissions for discovery-and-visibility or dynamic
  permissioning (linked from the prerequisites page)
