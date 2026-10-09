# The Britive side of an AWS organization onboarding: the "AWS" application,
# filled in from the outputs of the AWS stack that created the identity
# provider and the integration role in the management account
# (../../../aws/organization-stackset or single-account-stack, or the
# CloudFormation equivalents).
#
# Property names are the ones the provider accepts for this application
# type (its acceptance tests). Console equivalent:
# docs.britive.com/docs/onboarding-an-aws-application.

resource "britive_application" "aws" {
  application_type = "AWS"

  user_account_mappings {
    name        = var.account_mapping_attribute
    description = "Map Britive users to AWS by ${var.account_mapping_attribute}"
  }

  properties {
    name  = "displayName"
    value = var.application_name
  }
  properties {
    name  = "description"
    value = var.description
  }
  properties {
    name  = "showAwsAccountNumber"
    value = var.show_aws_account_numbers
  }

  # Connection properties: Management Account ID, Identity Provider Name,
  # Integration Role Name, Duration of the backend connection, Region.
  properties {
    name  = "accountId"
    value = var.management_account_id
  }
  properties {
    name  = "identityProvider"
    value = var.identity_provider_name
  }
  properties {
    name  = "roleName"
    value = var.integration_role_name
  }
  properties {
    name  = "sessionDuration"
    value = var.backend_connection_duration_hours
  }
  properties {
    name  = "region"
    value = var.region
  }

  properties {
    name  = "maxSessionDurationForProfiles"
    value = var.max_session_duration_for_profiles
  }
}
