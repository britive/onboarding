variable "tenant_name" {
  description = "Britive tenant subdomain, without '.britive-app.com'."
  type        = string
}

variable "saml_metadata_document_xml_content" {
  description = "Contents of the SAML metadata XML downloaded from the Britive tenant. Pass with -var=\"saml_metadata_document_xml_content=$(cat metadata.xml)\"."
  type        = string
}

variable "organizational_unit_ids" {
  description = "Organizational units the StackSet deploys to, including accounts that join them later. Use the root ID (r-xxxx) for the whole organization."
  type        = list(string)

  validation {
    condition     = length(var.organizational_unit_ids) > 0
    error_message = "Provide at least one OU or the root ID."
  }
}

variable "deploy_aws_invalidation_feature" {
  description = "Grant the permissions Britive's AWS session-invalidation feature needs, in the management account and every member account."
  type        = bool
  default     = true
}

variable "deploy_access_builder" {
  description = "Grant Access Builder permissions in the management account. Member accounts are not affected (the StackSet template does not offer it)."
  type        = bool
  default     = false
}

variable "deploy_ai_identity_scanning" {
  description = "Attach AmazonBedrockReadOnly in the management account."
  type        = bool
  default     = false
}

variable "max_session_duration" {
  description = "Integration role maximum session duration in seconds, management account."
  type        = number
  default     = 3600
}

variable "region" {
  description = "Region for the provider and for the StackSet instance. IAM is global, so one region is enough."
  type        = string
  default     = "us-east-1"
}

variable "call_as" {
  description = "SELF when running from the management account; DELEGATED_ADMIN when running from a delegated administrator account for StackSets."
  type        = string
  default     = "SELF"

  validation {
    condition     = contains(["SELF", "DELEGATED_ADMIN"], var.call_as)
    error_message = "call_as must be SELF or DELEGATED_ADMIN."
  }
}

variable "failure_tolerance_count" {
  description = "Accounts that may fail before the StackSet operation stops."
  type        = number
  default     = 10
}

variable "max_concurrent_count" {
  description = "Accounts deployed to in parallel."
  type        = number
  default     = 10
}
