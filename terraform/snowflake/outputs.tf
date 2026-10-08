# The fields the Britive Snowflake application asks for.
output "account_identifier" {
  description = "Enter as the Snowflake account identifier in the Britive application."
  value       = "${var.snowflake_organization}-${var.snowflake_account}"
}

output "username" {
  description = "Enter as the username in the Britive application."
  value       = snowflake_service_user.britive.name
}

output "role" {
  description = "Enter as the role in the Britive application."
  value       = snowflake_account_role.britive.name
}

output "orgadmin_granted" {
  description = "Whether the role holds ORGADMIN (organization application)."
  value       = var.grant_orgadmin
}
