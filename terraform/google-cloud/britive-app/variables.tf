variable "application_name" {
  description = "Display name of the application in Britive. Letters, digits and spaces only: the tenant rejects punctuation."
  type        = string
  default     = "Google Cloud"
  validation {
    condition     = can(regex("^[A-Za-z0-9 ]+$", var.application_name))
    error_message = "application_name may contain only letters, digits and spaces."
  }
}

variable "britive_users_domain" {
  description = "Email domain of your Britive users. Set it, with google_domain, when Britive users and Google identities use different domains: Britive then grants roles to <user>@<google_domain>. Null when the domains are the same."
  type        = string
  default     = null
}

variable "google_domain" {
  description = "Primary domain of your Google identities (Cloud Identity or Google Workspace). Used with britive_users_domain."
  type        = string
  default     = null
}

variable "programmatic_access" {
  description = "Also issue temporary service account keys at checkout for command-line use. Needs service account key creation allowed (organisation policy iam.disableServiceAccountKeyCreation). Console access is always on."
  type        = bool
  default     = false
}

variable "max_session_duration_seconds" {
  description = "Longest checkout any profile of this application may grant."
  type        = number
  default     = 43200
}

# Key mode only: read from ../../google-workspace when it has been applied.
variable "gsuite_admin_email" {
  description = "Key mode only. The Workspace user Britive acts as. Null reads it from ../../google-workspace."
  type        = string
  default     = null
}

variable "workspace_customer_id" {
  description = "Key mode only. Google Workspace customer ID. Null reads it from ../../google-workspace."
  type        = string
  default     = null
}
