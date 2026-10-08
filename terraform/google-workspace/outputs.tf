output "gsuite_admin_email" {
  description = "The Britive GCP application's \"G Suite admin\" field."
  value       = googleworkspace_user.britive.primary_email
}

output "workspace_customer_id" {
  description = "The Britive GCP application's \"Customer ID\" field."
  value       = var.workspace_customer_id
}
