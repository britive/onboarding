terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 7.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Everything Britive needs in this account. See ../modules/britive-integration.
module "britive" {
  source = "../modules/britive-integration"

  tenant_name                        = var.tenant_name
  saml_metadata_document_xml_content = var.saml_metadata_document_xml_content
  deploy_aws_invalidation_feature    = var.deploy_aws_invalidation_feature
  deploy_access_builder              = var.deploy_access_builder
  deploy_ai_identity_scanning        = var.deploy_ai_identity_scanning
  max_session_duration               = var.max_session_duration
  deploy_sample_roles                = var.deploy_sample_roles

  # Management account only: the AWS Identity Center and AWS Account Access
  # application types share this role.
  deploy_identity_center         = var.deploy_identity_center
  deploy_account_access          = var.deploy_account_access
  account_access_application_arn = var.account_access_application_arn
}
