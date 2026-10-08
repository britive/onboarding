output "azure_tenant_id" {
  description = "Enter as \"Azure Tenant ID\" in the Britive Azure WIF application."
  value       = local.tenant_id
}

output "azure_application_client_id" {
  description = "Enter as \"Azure Application (Client) ID\" in the Britive Azure WIF application."
  value       = azuread_application.britive.client_id
}

output "federated_credential_audience" {
  description = "Enter as \"Federated Credential Audience\" in the Britive Azure WIF application."
  value       = var.federated_credential_audience
}

output "britive_issuer_url" {
  description = "Issuer the federated credential trusts. Must equal the Britive application's Settings -> Britive Issuer URL; set britive_issuer_url if it does not."
  value       = local.issuer_url
}

output "service_principal_object_id" {
  description = "Object ID of the Britive service principal (the identity that holds the role assignments)."
  value       = azuread_service_principal.britive.object_id
}

output "graph_permissions_granted" {
  description = "Microsoft Graph application permissions consented to."
  value       = local.graph_permissions
}

output "britive_application_values" {
  description = "Every value to enter under Settings when creating the Azure WIF application in Britive."
  value = {
    azure_tenant_id               = local.tenant_id
    azure_application_client_id   = azuread_application.britive.client_id
    federated_credential_audience = var.federated_credential_audience
    britive_issuer_url            = local.issuer_url
    login_url                     = "https://portal.azure.com/"
    scan_ai_identities            = var.scan_ai_identities
  }
}
