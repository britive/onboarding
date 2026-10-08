# Resource addresses of the previous version of this module, so an existing
# deployment keeps its objects. To keep their names too, see "Upgrading from the
# previous version" in README.md.

moved {
  from = google_project.BritiveIntegration
  to   = google_project.britive[0]
}

moved {
  from = google_project_service.cloudresourcemanager
  to   = google_project_service.apis["cloudresourcemanager.googleapis.com"]
}

moved {
  from = google_project_service.iam
  to   = google_project_service.apis["iam.googleapis.com"]
}

moved {
  from = google_project_service.admin
  to   = google_project_service.apis["admin.googleapis.com"]
}

moved {
  from = google_organization_iam_custom_role.BritiveIntegration
  to   = google_organization_iam_custom_role.britive
}

moved {
  from = google_service_account.BritiveIntegration
  to   = google_service_account.britive
}

moved {
  from = google_service_account_key.BritiveIntegrationKey
  to   = google_service_account_key.britive[0]
}

moved {
  from = local_sensitive_file.key
  to   = local_sensitive_file.key[0]
}
