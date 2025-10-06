variable "tenant_name" {
  description = "Name of the Britive tenant. Omit '.britive-app.com'."
  type        = string
}

variable "saml_metadata_document_xml_content" {
  description = "The XML content of the SAML metadata document downloaded from the Britive tenant."
  type        = string
}

variable "deploy_aws_invalidation_feature" {
  description = "Enable AWS Invalidation feature permissions."
  type        = bool
  default     = true
}

variable "region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 instances. If not provided, you'll need to generate a key pair separately."
  type        = string
  default     = ""
}
