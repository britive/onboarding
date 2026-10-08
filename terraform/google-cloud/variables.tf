# ------------------------------------------------------------------ where Britive lives
variable "organization_id" {
  description = "Numeric ID of the Google Cloud organisation Britive will manage. `gcloud organizations list`."
  type        = string
  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "organization_id is the numeric organisation ID, e.g. 123456789012."
  }
}

variable "project_id" {
  description = "Project that holds the Britive service account (and, for WIF, the workload identity pool). Project IDs are unique across all of Google Cloud: pick your own, e.g. britive-integration-acme."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "create_project" {
  description = "true creates project_id. false uses an existing project of that ID."
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Display name of the project when it is created."
  type        = string
  default     = "Britive Integration"
}

variable "folder_id" {
  description = "Folder to create the project in (numeric ID). Null creates it directly under the organisation."
  type        = string
  default     = null
}

variable "billing_account" {
  description = "Billing account to link to a new project. Not needed for the APIs this module enables; set it if your organisation requires every project to have one."
  type        = string
  default     = null
}

variable "allow_project_deletion" {
  description = "false protects the project from `terraform destroy` (deleting it deletes the Britive service account and breaks the integration). Set true only when tearing the integration down."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- how Britive connects
variable "integration_type" {
  description = "\"wif\" (recommended): the Britive GCP WIF application, keyless, through workload identity federation. \"key\": the legacy Britive GCP application, with a service account key and Google Workspace domain-wide delegation (see ../google-workspace)."
  type        = string
  default     = "wif"
  validation {
    condition     = contains(["wif", "key"], var.integration_type)
    error_message = "integration_type must be \"wif\" or \"key\"."
  }
}

variable "britive_tenant_url" {
  description = "WIF only. Your Britive tenant, e.g. https://your-tenant.britive-app.com. The workload identity provider trusts its OAuth issuer."
  type        = string
  default     = null
  validation {
    condition     = var.britive_tenant_url == null || can(regex("^https://[a-z0-9.-]+$", var.britive_tenant_url))
    error_message = "britive_tenant_url must look like https://your-tenant.britive-app.com (no path, no trailing slash)."
  }
}

variable "britive_issuer_url" {
  description = "WIF only. Override for the issuer the provider trusts. Null derives <tenant>/api/auth/sso/oauth2; compare with the Britive app's Settings -> Britive Issuer URL."
  type        = string
  default     = null
}

# ----------------------------------------------------------------- what Britive may do
variable "access_scope" {
  description = "Where the Britive role is granted. \"organization\": every folder and project. \"folder\" or \"project\": only scope_id and what is beneath it."
  type        = string
  default     = "organization"
  validation {
    condition     = contains(["organization", "folder", "project"], var.access_scope)
    error_message = "access_scope must be \"organization\", \"folder\" or \"project\"."
  }
}

variable "scope_id" {
  description = "Folder number or project ID the role is granted on when access_scope is \"folder\" or \"project\". Ignored for \"organization\"."
  type        = string
  default     = null
}

variable "enable_bigquery_constraints" {
  description = "Add the permissions Britive needs to limit BigQuery roles to datasets and tables."
  type        = bool
  default     = true
}

variable "enable_apigee_constraints" {
  description = "Add the permissions Britive needs to limit roles to Apigee environments."
  type        = bool
  default     = false
}

variable "enable_ai_identity_scan" {
  description = "Add the permissions Britive needs to scan AI identities (Vertex AI reasoning engines)."
  type        = bool
  default     = false
}

# --------------------------------------------------------------------------- names
variable "role_id" {
  description = "ID of the organisation custom role. A deleted custom role keeps its ID reserved for weeks, so pick a new ID when re-creating the integration soon after a destroy."
  type        = string
  default     = "BritiveIntegrationRole"
}

variable "service_account_id" {
  description = "Account ID (the part before @) of the service account Britive uses."
  type        = string
  default     = "britive-integration"
}

variable "workload_identity_pool_id" {
  description = "WIF only. ID of the workload identity pool. A deleted pool keeps its ID reserved for 30 days."
  type        = string
  default     = "britive"
}

variable "workload_identity_provider_id" {
  description = "WIF only. ID of the OIDC provider in the pool."
  type        = string
  default     = "britive-oidc"
}
