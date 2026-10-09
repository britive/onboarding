variable "application_name" {
  description = "Display name of the application in Britive."
  type        = string
  default     = "AWS"
}

variable "description" {
  description = "Description shown on the application."
  type        = string
  default     = "AWS organization, integration managed with Terraform"
}

# ---- values from the AWS stack's outputs ---------------------------------
variable "management_account_id" {
  description = "Management account ID: output account_id of ../../../aws/single-account-stack (management account) or management_account_id of ../../../aws/organization-stackset."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be the 12-digit account ID."
  }
}

variable "identity_provider_name" {
  description = "Name of the SAML provider in AWS: output saml_provider_name / identity_provider_name (britive-<tenant>)."
  type        = string
}

variable "integration_role_name" {
  description = "Name of the integration role, not its ARN: output integration_role_name (britive-<tenant>-integration-role). Prefix a path without the leading slash if the role has one."
  type        = string
}

variable "backend_connection_duration_hours" {
  description = "Duration of the backend AWS connection in hours: output backend_connection_duration_hours. Must equal the role's maximum session duration."
  type        = number
  default     = 1

  validation {
    condition     = var.backend_connection_duration_hours >= 1 && var.backend_connection_duration_hours <= 12
    error_message = "backend_connection_duration_hours must be between 1 and 12 (3600-43200 seconds on the role)."
  }
}

variable "region" {
  description = "AWS region Britive calls STS in to generate temporary keys."
  type        = string
  default     = "us-east-1"
}

# ---- application behaviour -------------------------------------------------
variable "show_aws_account_numbers" {
  description = "Show AWS account numbers in the application."
  type        = bool
  default     = true
}

variable "max_session_duration_for_profiles" {
  description = "Longest expiration a profile on this application may have, in seconds (15 minutes to 12 hours for AWS). Cannot be lowered while a profile exceeds it."
  type        = number
  default     = 43200

  validation {
    condition     = var.max_session_duration_for_profiles >= 900 && var.max_session_duration_for_profiles <= 43200
    error_message = "max_session_duration_for_profiles must be between 900 and 43200 seconds."
  }
}

variable "account_mapping_attribute" {
  description = "Britive user attribute matched against the AWS account: Email or Username (the console's Account Mapping)."
  type        = string
  default     = "Email"
}
