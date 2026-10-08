# Britive-side example: tags, three profiles on an AWS application, each with
# a permission and a policy, showing the three common policy shapes:
# approval required, open to a tag, and restricted by source IP.
#
# The permissions reference the sample JIT roles the AWS templates in this
# repository create (DeploySampleRoles / deploy_sample_roles); scan the
# application in Britive first so they exist.

data "britive_identity_provider" "local" {
  name = var.identity_provider_name
}

data "britive_application" "aws" {
  name = var.application_name
}

# ---- tags ------------------------------------------------------------------

resource "britive_tag" "team" {
  name                 = var.team_tag_name
  description          = "May check out the AWS profiles"
  identity_provider_id = data.britive_identity_provider.local.id
}

resource "britive_tag_member" "team" {
  for_each = toset(var.team_members)

  tag_id   = britive_tag.team.id
  username = each.value
}

resource "britive_tag" "approvers" {
  name                 = var.approver_tag_name
  description          = "Approve Power User checkouts"
  identity_provider_id = data.britive_identity_provider.local.id
}

# ---- profile 1: Power User, approval required -----------------------------

resource "britive_profile" "power_user" {
  app_container_id                 = data.britive_application.aws.id
  name                             = "AWS Power User"
  description                      = "PowerUserAccess for one hour, approved by ${var.approver_tag_name}"
  expiration_duration              = "1h0m0s"
  extendable                       = true
  extension_duration               = "30m0s"
  extension_limit                  = 1
  notification_prior_to_expiration = "10m0s"
  destination_url                  = "https://console.aws.amazon.com/console/home"

  associations {
    type  = "Environment"
    value = var.environment_name
  }
}

resource "britive_profile_permission" "power_user" {
  profile_id      = britive_profile.power_user.id
  permission_name = "Poweruser-role"
  permission_type = "role"
}

resource "britive_profile_policy" "power_user" {
  profile_id  = britive_profile.power_user.id
  policy_name = "Power User with approval"
  description = "${var.team_tag_name} may check out after approval by ${var.approver_tag_name}"

  members = jsonencode({
    tags              = [{ name = britive_tag.team.name }]
    users             = []
    serviceIdentities = []
  })

  condition = jsonencode({
    approval = {
      approvers = {
        tags    = [britive_tag.approvers.name]
        userIds = []
      }
      notificationMedium = ["Email"]
      timeToApprove      = 30 # minutes the request stays open
      validFor           = 2  # hours an approval stays usable
      isValidForInDays   = false
    }
  })

  access_type  = "Allow"
  consumer     = "papservice"
  is_active    = true
  is_draft     = false
  is_read_only = false
}

# ---- profile 2: S3, no approval ------------------------------------------

resource "britive_profile" "s3" {
  app_container_id                 = data.britive_application.aws.id
  name                             = "AWS S3 Full Access"
  description                      = "AmazonS3FullAccess for one hour"
  expiration_duration              = "1h0m0s"
  extendable                       = false
  notification_prior_to_expiration = "10m0s"
  destination_url                  = "https://s3.console.aws.amazon.com/s3/home"

  associations {
    type  = "Environment"
    value = var.environment_name
  }
}

resource "britive_profile_permission" "s3" {
  profile_id      = britive_profile.s3.id
  permission_name = "S3-Fullaccess-role"
  permission_type = "role"
}

resource "britive_profile_policy" "s3" {
  profile_id  = britive_profile.s3.id
  policy_name = "S3 for the team"
  description = "${var.team_tag_name} may check out without approval"

  members = jsonencode({
    tags              = [{ name = britive_tag.team.name }]
    users             = []
    serviceIdentities = []
  })

  condition = jsonencode({})

  access_type  = "Allow"
  consumer     = "papservice"
  is_active    = true
  is_draft     = false
  is_read_only = false
}

# ---- profile 3: EC2, from allowed networks only ---------------------------

resource "britive_profile" "ec2" {
  app_container_id                 = data.britive_application.aws.id
  name                             = "AWS EC2 Full Access"
  description                      = "AmazonEC2FullAccess for one hour, from allowed networks"
  expiration_duration              = "1h0m0s"
  extendable                       = false
  notification_prior_to_expiration = "10m0s"
  destination_url                  = "https://console.aws.amazon.com/ec2/home"

  associations {
    type  = "Environment"
    value = var.environment_name
  }
}

resource "britive_profile_permission" "ec2" {
  profile_id      = britive_profile.ec2.id
  permission_name = "EC2-Fullaccess-role"
  permission_type = "role"
}

resource "britive_profile_policy" "ec2" {
  profile_id  = britive_profile.ec2.id
  policy_name = "EC2 from allowed networks"
  description = "${var.team_tag_name} may check out from ${var.allowed_ip_ranges}"

  members = jsonencode({
    tags              = [{ name = britive_tag.team.name }]
    users             = []
    serviceIdentities = []
  })

  condition = jsonencode({
    ipAddress = var.allowed_ip_ranges
  })

  access_type  = "Allow"
  consumer     = "papservice"
  is_active    = true
  is_draft     = false
  is_read_only = false
}
