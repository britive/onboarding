variable "britive_tenant_url" {
  description = "Your Britive tenant, e.g. https://your-tenant.britive-app.com. The federated credential trusts its OAuth issuer (<tenant>/api/auth/sso/oauth2)."
  type        = string

  validation {
    condition     = can(regex("^https://[a-z0-9.-]+$", var.britive_tenant_url))
    error_message = "britive_tenant_url must look like https://your-tenant.britive-app.com (no path, no trailing slash)."
  }
}

variable "britive_issuer_url" {
  description = "Override for the issuer the federated credential trusts. Null derives <britive_tenant_url>/api/auth/sso/oauth2; compare with the Britive application's Settings -> Britive Issuer URL and set this if they differ."
  type        = string
  default     = null
}

variable "integration_mode" {
  description = "\"discovery\": Britive scans the tenant (Reader at the Tenant Root Group, Directory.Read.All). \"dynamic\": Britive also grants Azure roles and group memberships at checkout (custom role with role-assignment write, plus the Graph write permissions)."
  type        = string
  default     = "dynamic"

  validation {
    condition     = contains(["discovery", "dynamic"], var.integration_mode)
    error_message = "integration_mode must be \"discovery\" or \"dynamic\"."
  }
}

variable "scan_ai_identities" {
  description = "Also let Britive discover Azure AI Foundry agents: assigns ai_identity_role_name at the Tenant Root Group and corresponds to \"Scan AI Identities\" on the Britive application."
  type        = bool
  default     = false
}

variable "ai_identity_role_name" {
  description = "Built-in role Britive's prerequisites name for scanning AI identities."
  type        = string
  default     = "Foundry User"
}

variable "enable_last_sign_in" {
  description = "Grant AuditLog.Read.All so Britive can read each user's last sign-in date. Needs a Microsoft Entra ID P1 or P2 licence to return data; Britive skips the field without the permission."
  type        = bool
  default     = true
}

variable "application_name" {
  description = "Display name of the app registration. Britive's guide uses \"Britive\"."
  type        = string
  default     = "Britive"
}

variable "custom_role_name" {
  description = "Name of the custom role created in dynamic mode."
  type        = string
  default     = "Britive-Integration-Role"
}

variable "federated_credential_subject" {
  description = "Subject claim of the tokens the Britive tenant presents. Britive's guide specifies sys@britive.com."
  type        = string
  default     = "sys@britive.com"
}

variable "federated_credential_audience" {
  description = "Audience of the federated credential. Keep Azure's default unless you change it on both sides; enter the same value as \"Federated Credential Audience\" in the Britive application."
  type        = string
  default     = "api://AzureADTokenExchange"
}

variable "subscription_id" {
  description = "Any subscription in the tenant, for the azurerm provider to initialise. Null reads ARM_SUBSCRIPTION_ID."
  type        = string
  default     = null
}
