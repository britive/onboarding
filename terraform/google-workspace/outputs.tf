output "gsuite_admin_email" {
  description = "The Britive GCP application's \"G Suite admin\" / \"Custom user email\" field."
  value       = googleworkspace_user.britive.primary_email
}

output "workspace_customer_id" {
  description = "The Britive GCP application's \"Customer ID\" field."
  value       = var.workspace_customer_id
}

output "initial_password" {
  description = "Generated password of the Workspace user, for the one-time interactive sign-in Britive's prerequisites ask for. terraform output -raw initial_password"
  value       = random_password.admin.result
  sensitive   = true
}
