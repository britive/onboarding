variable "workspace_customer_id" {
  description = "Google Workspace customer ID: admin.google.com -> Account -> Account settings -> Customer ID (starts with C)."
  type        = string
}

variable "workspace_domain" {
  description = "Primary domain of the Workspace account, e.g. example.com."
  type        = string
}

variable "workspace_impersonation_email" {
  description = "An existing Workspace super administrator Terraform acts as (through domain-wide delegation) to create the role and the user."
  type        = string
}

variable "service_account_key_file" {
  description = "Key of the Britive service account, written by ../google-cloud in key mode."
  type        = string
  default     = "../google-cloud/keys/key.json"
}

variable "admin_role_name" {
  description = "Name of the Workspace admin role created for Britive."
  type        = string
  default     = "Britive Integration"
}

variable "admin_user_name" {
  description = "Local part of the Workspace user Britive acts as; the user is <admin_user_name>@<workspace_domain>."
  type        = string
  default     = "britive-integration"
}
