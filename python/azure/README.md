# Azure

The Python script that used to live here was removed: it depended on
`azure-graphrbac`, which targets the Azure AD Graph API Microsoft retired,
and it assigned the custom role at subscription scope where Britive requires
the Tenant Root Group. It could not run against a current tenant.

Follow the product steps directly:

- [Azure prerequisites](https://docs.britive.com/docs/prerequisites-azure)
- [Registering the Britive application in Azure](https://docs.britive.com/docs/registering-britive-application-in-azure)
- Assigning permissions for discovery-and-visibility or dynamic
  permissioning (linked from the prerequisites page)

A Terraform example (`azuread` application registration + federated
credential, custom role at the Tenant Root Group) is planned under
`terraform/azure/`.
