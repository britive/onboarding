variable "tenant_name" {
  description = "Britive tenant subdomain, without '.britive-app.com'. Used in the SAML provider and role names."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.tenant_name))
    error_message = "tenant_name must contain only letters, digits and hyphens (the part before .britive-app.com)."
  }
}

variable "saml_metadata_document_xml_content" {
  description = "Contents of the SAML metadata XML downloaded from the Britive tenant (System Administration > Security > SAML Configurations > Download SAML Metadata)."
  type        = string

  validation {
    condition     = can(regex("EntityDescriptor", var.saml_metadata_document_xml_content))
    error_message = "saml_metadata_document_xml_content must be the SAML metadata XML itself, not a file path."
  }
}

variable "deploy_aws_invalidation_feature" {
  description = "Grant the integration role the IAM policy permissions Britive's AWS session-invalidation feature needs, scoped to arn:aws:iam::<account>:policy/britive/managed/*."
  type        = bool
  default     = true
}

variable "deploy_access_builder" {
  description = "Grant the integration role the IAM role permissions Britive Access Builder needs to create Britive-managed roles, scoped to arn:aws:iam::<account>:role/britive/managed/*."
  type        = bool
  default     = false
}

variable "deploy_ai_identity_scanning" {
  description = "Attach AmazonBedrockReadOnly so Britive can scan AI identities in this account."
  type        = bool
  default     = false
}

variable "max_session_duration" {
  description = "Maximum session duration of the integration role in seconds (3600-43200). Enter the same value, in hours, as 'Duration of backend connection' when creating the AWS application in Britive."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "deploy_identity_center" {
  description = "Management account only. Grant the Identity Center, Organizations and IAM policy read permissions the Britive 'AWS Identity Center' application needs to scan permission sets, groups and applications and to assign them at checkout."
  type        = bool
  default     = false
}

variable "deploy_account_access" {
  description = "Management account only. Grant the account access manager permissions the Britive 'AWS Account Access' application needs to create and delete entitlements. Requires account_access_application_arn; enable the account access manager in the Identity Center primary region first."
  type        = bool
  default     = false
}

variable "account_access_application_arn" {
  description = "ARN of the account access manager application, from its Settings page in the management account (begins with arn:aws:account-access:). Not the 'AWS account access' application listed in IAM Identity Center (arn:aws:sso::), which fails the connection test."
  type        = string
  default     = ""

  validation {
    condition     = var.account_access_application_arn == "" || can(regex("^arn:aws[a-z-]*:account-access:[a-z0-9-]+:[0-9]{12}:application/", var.account_access_application_arn))
    error_message = "account_access_application_arn must begin with arn:aws:account-access:<region>:<account>:application/ (the account access manager Settings page shows it), or be empty."
  }
}

variable "deploy_sample_roles" {
  description = "Create four sample JIT roles (ReadOnly, PowerUser, EC2 full access, S3 full access) trusting the Britive SAML provider, for demonstrations."
  type        = bool
  default     = false
}

variable "sample_role_max_session_duration" {
  description = "Maximum session duration of the sample roles in seconds."
  type        = number
  default     = 3600
}
