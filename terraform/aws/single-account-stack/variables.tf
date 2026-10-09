variable "tenant_name" {
  description = "Britive tenant subdomain, without '.britive-app.com'."
  type        = string
}

variable "saml_metadata_document_xml_content" {
  description = "Contents of the SAML metadata XML downloaded from the Britive tenant. Use file(\"path\") in terraform.tfvars is not possible; paste the XML or load it with -var=\"saml_metadata_document_xml_content=$(cat metadata.xml)\"."
  type        = string
}

variable "deploy_aws_invalidation_feature" {
  description = "Grant the permissions Britive's AWS session-invalidation feature needs."
  type        = bool
  default     = true
}

variable "deploy_access_builder" {
  description = "Grant the permissions Britive Access Builder needs to create roles under role/britive/managed/*."
  type        = bool
  default     = false
}

variable "deploy_ai_identity_scanning" {
  description = "Attach AmazonBedrockReadOnly so Britive can scan AI identities."
  type        = bool
  default     = false
}

variable "max_session_duration" {
  description = "Integration role maximum session duration in seconds (3600-43200). Enter the same value in hours as 'Duration of backend connection' in Britive."
  type        = number
  default     = 3600
}

variable "deploy_sample_roles" {
  description = "Also create four sample JIT roles for a demonstration (the equivalent of DeploySampleRoles=true on the CloudFormation template)."
  type        = bool
  default     = false
}

variable "deploy_identity_center" {
  description = "Management account only. Add the permissions the Britive 'AWS Identity Center' application needs (identitystore, sso, organizations) to the integration role."
  type        = bool
  default     = false
}

variable "deploy_account_access" {
  description = "Management account only. Add the permissions the Britive 'AWS Account Access' application needs to the integration role. Requires account_access_application_arn."
  type        = bool
  default     = false
}

variable "account_access_application_arn" {
  description = "ARN of the account access manager application from its Settings page (arn:aws:account-access:<region>:<account>:application/...). Required when deploy_account_access is true."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region for the provider. IAM is global; any region works."
  type        = string
  default     = "us-east-1"
}
