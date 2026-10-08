variable "application_name" {
  description = "Name of the AWS application in Britive the profiles are created on (System Administration > Tenant Applications)."
  type        = string
  default     = "AWS Standalone"
}

variable "environment_name" {
  description = "Environment the profiles are associated with: the account name as the application scan shows it."
  type        = string
}

variable "identity_provider_name" {
  description = "Identity provider the tags are created on. Only tags on the local Britive provider can be managed with Terraform."
  type        = string
  default     = "Britive"
}

variable "team_tag_name" {
  description = "Tag whose members may check the profiles out."
  type        = string
  default     = "aws-developers"
}

variable "team_members" {
  description = "Usernames to add to the team tag. Leave empty to manage membership elsewhere."
  type        = list(string)
  default     = []
}

variable "approver_tag_name" {
  description = "Tag whose members approve the Power User checkout."
  type        = string
  default     = "aws-approvers"
}

variable "allowed_ip_ranges" {
  description = "Source IP ranges from which the EC2 profile may be checked out (comma separated CIDRs or addresses)."
  type        = string
  default     = "10.0.0.0/8,192.168.0.0/16"
}
