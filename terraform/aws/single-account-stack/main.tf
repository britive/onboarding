terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# SAML Provider
resource "aws_iam_saml_provider" "britive" {
  name                   = "britive-${var.tenant_name}"
  saml_metadata_document = var.saml_metadata_document_xml_content
}

# Integration Role
resource "aws_iam_role" "britive_integration" {
  name                 = "britive-${var.tenant_name}-integration-role"
  description          = "Britive Integration Role"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRoleWithSAML",
          "sts:SetSourceIdentity",
          "sts:TagSession"
        ]
        Principal = {
          Federated = aws_iam_saml_provider.britive.arn
        }
        Condition = {
          StringEquals = {
            "SAML:aud" = "https://signin.aws.amazon.com/saml"
          }
        }
      }
    ]
  })
}

# Attach IAM ReadOnly Access policy
resource "aws_iam_role_policy_attachment" "britive_integration_iam_readonly" {
  role       = aws_iam_role.britive_integration.name
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}

# Attach Organizations ReadOnly Access policy
resource "aws_iam_role_policy_attachment" "britive_integration_orgs_readonly" {
  role       = aws_iam_role.britive_integration.name
  policy_arn = "arn:aws:iam::aws:policy/AWSOrganizationsReadOnlyAccess"
}

# AWS Invalidation Feature Policy (conditional)
resource "aws_iam_role_policy" "aws_invalidation" {
  count = var.deploy_aws_invalidation_feature ? 1 : 0

  name = "aws-invalidation"
  role = aws_iam_role.britive_integration.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = "arn:aws:iam::*:policy/britive/managed/*"
      }
    ]
  })
}
