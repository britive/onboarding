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
  description = "The region where the stacks will be created. All resources are IAM global resources so only one region is required."
  type        = string
  default     = "us-east-1"
}

variable "root_ou_id" {
  description = "The ID of the Root OU where the StackSet will be deployed."
  type        = string
}

variable "s3_bucket_name" {
  description = "The name of the S3 bucket that holds the britive_integration_resources.yaml CloudFormation template."
  type        = string
  default     = "britive-global-artifacts-public"
}

variable "s3_key_for_iam_resources_template" {
  description = "The S3 key for britive_integration_resources.yaml object in the S3 bucket. Do not include a leading /."
  type        = string
  default     = "britive_integration_resources.yaml"
}
