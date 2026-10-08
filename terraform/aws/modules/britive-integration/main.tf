# Britive AWS integration: the SAML identity provider and the integration role
# Britive assumes to scan the account, plus the optional permissions for the
# session-invalidation feature, Access Builder and AI identity scanning.
#
# Matches https://docs.britive.com/docs/configuring-identity-provider,
# configuring-iam-roles and configuring-for-session-invalidation.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Every role Britive brokers must grant these three actions to the SAML
  # provider. SetSourceIdentity is required once a Source Identity attribute is
  # configured on the Britive application; TagSession by session invalidation.
  saml_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_saml_provider.britive.arn
        }
        Action = [
          "sts:AssumeRoleWithSAML",
          "sts:SetSourceIdentity",
          "sts:TagSession",
        ]
        Condition = {
          StringEquals = {
            "SAML:aud" = "https://signin.aws.amazon.com/saml"
          }
        }
      }
    ]
  })

  sample_roles = var.deploy_sample_roles ? {
    readonly  = { name = "Readonly-admin-role", description = "Sample Britive JIT role: read-only access", policy = "ReadOnlyAccess" }
    poweruser = { name = "Poweruser-role", description = "Sample Britive JIT role: PowerUserAccess", policy = "PowerUserAccess" }
    ec2_admin = { name = "EC2-Fullaccess-role", description = "Sample Britive JIT role: EC2 full access", policy = "AmazonEC2FullAccess" }
    s3_admin  = { name = "S3-Fullaccess-role", description = "Sample Britive JIT role: S3 full access", policy = "AmazonS3FullAccess" }
  } : {}
}

resource "aws_iam_saml_provider" "britive" {
  name                   = "britive-${var.tenant_name}"
  saml_metadata_document = var.saml_metadata_document_xml_content
}

resource "aws_iam_role" "britive_integration" {
  name                 = "britive-${var.tenant_name}-integration-role"
  description          = "Assumed by Britive to scan this account and, optionally, manage Britive-managed policies and roles"
  max_session_duration = var.max_session_duration
  assume_role_policy   = local.saml_trust_policy
}

resource "aws_iam_role_policy_attachment" "iam_readonly" {
  role       = aws_iam_role.britive_integration.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/IAMReadOnlyAccess"
}

# Needed in the management account to discover the organization; harmless in
# member accounts, where it returns nothing.
resource "aws_iam_role_policy_attachment" "organizations_readonly" {
  role       = aws_iam_role.britive_integration.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AWSOrganizationsReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "bedrock_readonly" {
  count = var.deploy_ai_identity_scanning ? 1 : 0

  role       = aws_iam_role.britive_integration.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonBedrockReadOnly"
}

# Session invalidation: Britive writes deny policies under policy/britive/managed/
# to cut live sessions short. Pair with the SCP in ../../../../cloudformation/aws/scp/
# so nothing but this role can touch that path.
resource "aws_iam_role_policy" "aws_invalidation" {
  count = var.deploy_aws_invalidation_feature ? 1 : 0

  name = "britive-aws-invalidation"
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
          "iam:ListPolicyVersions",
        ]
        Resource = "arn:${local.partition}:iam::${local.account_id}:policy/britive/managed/*"
      }
    ]
  })
}

# Access Builder: Britive creates and removes roles under role/britive/managed/.
resource "aws_iam_role_policy" "access_builder" {
  count = var.deploy_access_builder ? 1 : 0

  name = "britive-access-builder"
  role = aws_iam_role.britive_integration.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
        ]
        Resource = "arn:${local.partition}:iam::${local.account_id}:role/britive/managed/*"
      }
    ]
  })
}

# Sample JIT roles for demonstrations. Each trusts the Britive SAML provider
# exactly as a production role must.
resource "aws_iam_role" "sample" {
  for_each = local.sample_roles

  name                 = each.value.name
  description          = each.value.description
  max_session_duration = var.sample_role_max_session_duration
  assume_role_policy   = local.saml_trust_policy
}

resource "aws_iam_role_policy_attachment" "sample" {
  for_each = local.sample_roles

  role       = aws_iam_role.sample[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value.policy}"
}
