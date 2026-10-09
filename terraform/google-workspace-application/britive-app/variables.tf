variable "application_name" {
  description = "Display name of the application in Britive. Letters, digits and spaces only: the tenant rejects punctuation."
  type        = string
  default     = "Google Workspace"
  validation {
    condition     = can(regex("^[A-Za-z0-9 ]+$", var.application_name))
    error_message = "application_name may contain only letters, digits and spaces."
  }
}

variable "gsuite_admin_email" {
  description = "The Workspace user Britive acts as (the application's Google Workspace Admin Email). Null reads gsuite_admin_email from ../../google-workspace."
  type        = string
  default     = null
}

variable "login_url" {
  description = "URL users open at checkout (the application's Login URL)."
  type        = string
  default     = "https://admin.google.com"
}

variable "create_user_for_super_admin" {
  description = "Create user account for super admin role: at checkout of a super admin profile Britive creates <user>_britive@<domain> with a random password and the role, and suspends it at checkin."
  type        = bool
  default     = false
}

variable "scan_roles" {
  description = "Scan admin roles so they can be granted in profiles."
  type        = bool
  default     = true
}

variable "scan_groups" {
  description = "Scan groups so memberships can be granted in profiles."
  type        = bool
  default     = true
}

variable "enable_sso" {
  description = "Use Britive as the SAML identity provider for Google Workspace (the application's SSO Settings). Also needs the Workspace side configured: docs.britive.com/docs/configuring-sso-gcds-gws."
  type        = bool
  default     = false
}

variable "britive_users_domain" {
  description = "Email domain of your Britive users. Set it with google_domain when it differs from the Workspace primary domain (the application's Use another domain for account mapping)."
  type        = string
  default     = null
}

variable "google_domain" {
  description = "Primary domain in Google Workspace, when it differs from britive_users_domain. Null reads workspace_domain from ../."
  type        = string
  default     = null
}

variable "max_session_duration_seconds" {
  description = "Longest checkout any profile of this application may grant (15 minutes to 7 days)."
  type        = number
  default     = 43200
}
