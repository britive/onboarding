# Member accounts: a service-managed StackSet deploys the CloudFormation
# template from this repository to every account under the target OUs and to
# accounts that join later. The template body is read from the repository, so
# nothing has to be uploaded to S3 first.

locals {
  member_template = "${path.module}/../../../cloudformation/aws/britive_integration_resources.yaml"
}

resource "aws_cloudformation_stack_set" "britive_resources" {
  name             = "britive-resources-${var.tenant_name}"
  description      = "Britive SAML identity provider and integration role in every member account"
  permission_model = "SERVICE_MANAGED"
  call_as          = var.call_as
  capabilities     = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM"]
  template_body    = file(local.member_template)

  parameters = {
    SamlMetadataDocumentXmlContent = var.saml_metadata_document_xml_content
    TenantName                     = var.tenant_name
    # The template's AllowedValues are the strings "true" and "false".
    DeployAwsInvalidationFeature = var.deploy_aws_invalidation_feature ? "true" : "false"
    DeployAccessBuilder          = var.deploy_access_builder ? "true" : "false"
    DeployAiIdentityScanning     = var.deploy_ai_identity_scanning ? "true" : "false"
    DeploySampleRoles            = "false"
    MaxSessionDuration           = tostring(var.max_session_duration)
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  managed_execution {
    active = true
  }

  operation_preferences {
    failure_tolerance_count = var.failure_tolerance_count
    max_concurrent_count    = var.max_concurrent_count
    region_concurrency_type = "PARALLEL"
  }
}

resource "aws_cloudformation_stack_set_instance" "britive_resources" {
  stack_set_name = aws_cloudformation_stack_set.britive_resources.name
  region         = var.region
  call_as        = var.call_as

  deployment_targets {
    organizational_unit_ids = var.organizational_unit_ids
  }

  operation_preferences {
    failure_tolerance_count = var.failure_tolerance_count
    max_concurrent_count    = var.max_concurrent_count
    region_concurrency_type = "PARALLEL"
  }
}
