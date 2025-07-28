terraform {
  required_providers {
    britive = {
      source  = "britive/britive"
      version = ">= 2.1.0, < 2.1.5"
    }
  }
}

provider "britive" {
  tenant = var.britive-tenant
  token = var.britive-token 
}

## Manage Local Tags
data "britive_identity_provider" "idp" {
    name = "Britive" # Get Identity provider with the name Britive
}

resource "britive_tag" "k8s_users" {
    name = "k8s users"
    description = "EKS end users for demo"
    identity_provider_id = data.britive_identity_provider.idp.id
}

resource "britive_tag" "aws_admins" {
    name = "AWS admins"
    description = "Admins to manage k8s application on Britive"
    identity_provider_id = data.britive_identity_provider.idp.id
}

resource "britive_tag" "s3_developers" {
    name = "S3 developers"
    description = "EKS developers"
    identity_provider_id = data.britive_identity_provider.idp.id
}

resource "britive_tag_member" "k8s_users_member1" {
    tag_id = britive_tag.k8s_users.id
    username = "britive-learning01@britive.com"
}

resource "britive_tag_member" "k8s_users_member2" {
    tag_id = britive_tag.k8s_users.id
    username = "jane.doe@britive.com"
}
resource "britive_tag_member" "k8s_users_member3" {
    tag_id = britive_tag.k8s_users.id
    username = "john.doe@britive.com"
}

## Get App id of the applications we want to create a profile for

data "britive_application" "eks" {
    name = "EKS" # Name of the application in the Britive Environment
}

data "britive_application" "aws" {
    name = "AWS Standalone - Vin" # Name of the application in the Britive Environment
}

/* output "eks_id" {
  description = "Id of the EKS Application on Britive"
  value = data.britive_application.eks.id   # id of the application fetched in the data step
  sensitive = false
}
 */

## Britive Profile and policy definitions

# Profile 01 - EKS
resource "britive_profile" "jit-admins" {
    app_container_id                 = data.britive_application.eks.id
    name                             = "JIT Admins"
    description                      = "Admins of the JIT Namespace"
    expiration_duration              = "45m0s"
    extendable                       = false
    notification_prior_to_expiration = "05m0s"
    extension_duration               = "00m00s"
    extension_limit                  = 0
    associations {
      type  = "Environment"
      value = "cluster01"
    }
    destination_url                  = ""
}
# Add a permission (group) to the profile
resource "britive_profile_permission" "jit-admins" {
    profile_id = britive_profile.jit-admins.id
    permission_name = "jit-admins"
    permission_type = "Group"
}

# Add a profile policy
resource "britive_profile_policy" "jit-admins-default" {
    profile_id   = britive_profile.jit-admins.id
    policy_name  = "Default policy for JIT Admins"
    description  = "policy granting access to jit admins"
    members      = jsonencode(
        {
            tags              = [
              {
                name = "k8s users"
              },
            ]
        }
    )
    condition    = jsonencode(
        {
            approval     = {
                approvers          = {
                    tags    = [
                        "Team Terminator",
                    ]
                    userIds = [
                        "john.doe@britive.com"                        
                    ]
                }
                isValidForInDays   = true
                notificationMedium = [
                    "Email with Magic Link"
                ]
                timeToApprove      = 630
                validFor           = 2
            }
        }
    )
    access_type  = "Allow"
    consumer     = "papservice"   
    is_active    = true
    is_draft     = false
    is_read_only = false
}


# Profile 2 - AWS
resource "britive_profile" "power-user" {
    app_container_id                 = data.britive_application.aws.id
    name                             = "AWS Power User"
    description                      = "Power Users of the AWS Account for management"
    expiration_duration              = "1h0m0s"
    extendable                       = false
    notification_prior_to_expiration = "05m0s"
    extension_duration               = "00m00s"
    extension_limit                  = 0
    associations {
      type  = "Environment"
      value = "Labs Account"
    }
    destination_url                  = "https://console.aws.amazon.com/console/home"
}
# Add a permission (group) to the profile
resource "britive_profile_permission" "power-user" {
    profile_id = britive_profile.power-user.id
    permission_name = "Poweruser-role"
    permission_type = "role"
}

# Add a profile policy
resource "britive_profile_policy" "account-admins-default" {
    profile_id   = britive_profile.power-user.id
    policy_name  = "Default policy for Power Users"
    description  = "policy granting access to power users"
    members      = jsonencode(
        {
            tags              = [
              {
                name = "AWS Power Users"     # This tag could be a local britive tag or a tag from the identity provider such as Okta or Azure AD
              },
            ]
        }
    )
    condition    = jsonencode(
        {
            approval     = {            # Approval condition for the profile when the profile is being checked-out by the user.
                approvers          = {
                    tags    = [
                        "Team Terminator",
                    ]
                    userIds = [
                        ""                        
                    ]
                }
                isValidForInDays   = true
                notificationMedium = [
                    "Email with Magic Link"     # Additional notification medium can be added such as Slack, Teams, etc.
                ]
                timeToApprove      = 630
                validFor           = 2
            }
        }
    )
    access_type  = "Allow"
    consumer     = "papservice"
    is_active    = true
    is_draft     = false
    is_read_only = false
}

# Profile 3 - AWS S3-Fullaccess-role
resource "britive_profile" "s3-access" {
    app_container_id                 = data.britive_application.aws.id
    name                             = "AWS S3 Admins"
    description                      = "Admins of the S3 Service"
    expiration_duration              = "1h0m0s"
    extendable                       = false
    notification_prior_to_expiration = "05m0s"
    extension_duration               = "00m00s"
    extension_limit                  = 0
    associations {
      type  = "Environment"
      value = "Labs Account"    # Update based on the scanned in account name or organization name
    }
    destination_url                  = "https://console.aws.amazon.com/console/home"
}
# Add a permission (group) to the profile
resource "britive_profile_permission" "S3Access" {
    profile_id = britive_profile.s3-access.id
    permission_name = "S3-Fullaccess-role"
    permission_type = "role"
}

# Add a profile policy
resource "britive_profile_policy" "s3-access-default" {
    profile_id   = britive_profile.s3-access.id
    policy_name  = "Default policy for S3 Admins"
    description  = "policy granting access to S3 admins"
    members      = jsonencode(
        {
            tags              = [
              {
                name = [
                    "S3 developers",
                    "AWS Account Admins"
                    ]       # This tag could be a local britive tag or a tag from the identity provider such as Okta or Azure AD
              },
            ]
        }
    )
    condition    = jsonencode(
        {
            approval     = {
                approvers          = {
                    tags    = [
                        "Team Terminator",
                    ]
                    channelIds = [
                        "channel_id_01",
                        "channel_id_02"
                    ]
                }
                isValidForInDays   = true
                notificationMedium = [
                    "Email with Magic Link",
                    "Slack"  # Additional notification medium can be added such as Teams, etc.
                ]
                timeToApprove      = 630
                validFor           = 4
            }
        }
    )
    access_type  = "Allow"
    consumer     = "papservice"
    is_active    = true
    is_draft     = false
    is_read_only = false
}

# Profile 4 - AWS EC2-Fullaccess-role
resource "britive_profile" "ec2-admin" {
    app_container_id                 = data.britive_application.aws.id
    name                             = "AWS EC2 Admins"
    description                      = "Admins of the EC2 instances in the AWS Account for management"
    expiration_duration              = "1h0m0s"
    extendable                       = false
    notification_prior_to_expiration = "05m0s"
    extension_duration               = "00m00s"
    extension_limit                  = 0
    associations {
      type  = "Environment"
      value = "Labs Account"
    }
    destination_url                  = "https://console.aws.amazon.com/console/home"
}

# Add a permission (group) to the profile
resource "britive_profile_permission" "ec2Admin" {
    profile_id = britive_profile.ec2-admin.id
    permission_name = "EC2-Fullaccess-role"
    permission_type = "role"
}

# Add a profile policy
resource "britive_profile_policy" "ec2-admin-default" {
    profile_id   = britive_profile.ec2-admin.id
    policy_name  = "Default policy for EC2 Admins"
    description  = "policy granting access to ec2 admins"
    members      = jsonencode(
        {
            tags              = [
              {
                name = "Server Admins"     # This tag could be a local britive tag or a tag from the identity provider such as Okta or Azure AD
              },
            ]
        }
    )
    condition    = jsonencode(
        {
            ipAddress    = "192.162.0.0/16,10.10.0.10"  # IP address condition for the profile when the profile is being checked-out by the user.
        }
    )
    access_type  = "Allow"
    consumer     = "papservice"
    is_active    = true
    is_draft     = false
    is_read_only = false
}
