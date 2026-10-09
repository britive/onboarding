terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 7.0"
    }
  }
}

# Run with credentials for the organization's management account (or a
# delegated administrator for CloudFormation StackSets).
provider "aws" {
  region = var.region
}

# The management account itself: service-managed StackSets never deploy to
# it, yet the Britive "AWS" application type requires the identity provider
# and integration role there. See ../modules/britive-integration.
module "britive_management_account" {
  source = "../modules/britive-integration"

  tenant_name                        = var.tenant_name
  saml_metadata_document_xml_content = var.saml_metadata_document_xml_content
  deploy_aws_invalidation_feature    = var.deploy_aws_invalidation_feature
  deploy_access_builder              = var.deploy_access_builder
  deploy_ai_identity_scanning        = var.deploy_ai_identity_scanning
  max_session_duration               = var.max_session_duration

  # Identity Center and the account access manager live in the management
  # account only; stackset.tf never passes these to member accounts.
  deploy_identity_center         = var.deploy_identity_center
  deploy_account_access          = var.deploy_account_access
  account_access_application_arn = var.account_access_application_arn
}
