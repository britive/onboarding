# This module creates resources in the master account
# For organization-wide deployment, we create a StackSet

# CloudFormation StackSet for Organization-wide deployment
resource "aws_cloudformation_stack_set" "britive_resources" {
  name             = "britive-resources-${var.tenant_name}"
  description      = "Deploys required Britive IAM resources"
  permission_model = "SERVICE_MANAGED"
  capabilities     = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM"]

  template_url = "https://${var.s3_bucket_name}.s3.amazonaws.com/${var.s3_key_for_iam_resources_template}"

  parameters = {
    SamlMetadataDocumentXmlContent = var.saml_metadata_document_xml_content
    TenantName                     = var.tenant_name
    DeployAwsInvalidationFeature   = var.deploy_aws_invalidation_feature ? "yes" : "no"
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  managed_execution {
    active = true
  }

  operation_preferences {
    failure_tolerance_count = 10
    max_concurrent_count    = 10
    region_concurrency_type = "PARALLEL"
  }
}

# StackSet instance deployment to organizational units
resource "aws_cloudformation_stack_set_instance" "britive_resources" {
  stack_set_name = aws_cloudformation_stack_set.britive_resources.name
  region         = var.region

  deployment_targets {
    organizational_unit_ids = [var.root_ou_id]
  }

  operation_preferences {
    failure_tolerance_count = 10
    max_concurrent_count    = 10
    region_concurrency_type = "PARALLEL"
  }
}
