variable "tenant_name" {
  description = "Name of the Britive tenant. Omit '.britive-app.com'."
  type        = string
}

variable "saml_metadata_document_xml_content" {
  description = "The XML content of the SAML metadata document downloaded from the Britive tenant."
  type        = string
}

variable "deploy_aws_invalidation_feature" {
  description = "A flag used to indicate whether additional IAM permissions should be added to the integration role in support of the Britive AWS Invalidation feature."
  type        = bool
  default     = true
}

variable "region" {
  description = "AWS region (resources are global IAM, region is for provider configuration only)."
  type        = string
  default     = "us-east-1"
}
