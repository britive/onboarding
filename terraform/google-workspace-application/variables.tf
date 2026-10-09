# ------------------------------------------------------------------ project
variable "project_id" {
  description = "Google Cloud project that holds the Britive service account. Created when create_project is true; otherwise it must exist."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "create_project" {
  description = "Create the project. false uses an existing project_id (you need rights to enable APIs and create service accounts and keys in it)."
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Display name of the project when it is created."
  type        = string
  default     = "Britive Google Workspace"
}

variable "organization_id" {
  description = "Google Cloud organisation the new project is created under. Null with folder_id null creates a project without a parent, which only works for accounts that have no organisation."
  type        = string
  default     = null
}

variable "folder_id" {
  description = "Folder to create the project in instead of the organisation root."
  type        = string
  default     = null
}

variable "billing_account" {
  description = "Billing account to attach to the new project. The Admin SDK API is free; a billing account is only required when your organisation policy demands one."
  type        = string
  default     = null
}

variable "allow_project_deletion" {
  description = "Let terraform destroy delete the project. Off by default: deleting it deletes the service account Britive signs in with."
  type        = bool
  default     = false
}

# ------------------------------------------------------- service account
variable "service_account_id" {
  description = "Account ID of the Britive service account (<id>@<project>.iam.gserviceaccount.com)."
  type        = string
  default     = "britive-workspace"
}

variable "workspace_domain" {
  description = "Primary domain of the Google Workspace account, e.g. example.com. Used only in the printed guidance and the application values."
  type        = string
}
