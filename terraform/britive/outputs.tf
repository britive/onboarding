output "profile_ids" {
  description = "IDs of the three profiles, keyed by name."
  value = {
    (britive_profile.power_user.name) = britive_profile.power_user.id
    (britive_profile.s3.name)         = britive_profile.s3.id
    (britive_profile.ec2.name)        = britive_profile.ec2.id
  }
}

output "tags" {
  description = "Tags created on the local identity provider."
  value       = [britive_tag.team.name, britive_tag.approvers.name]
}
