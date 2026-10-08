# integration_type = "key" (legacy): a service account key that the Britive GCP
# application stores. Prefer "wif", which needs no key.
#
# The key is written to keys/key.json (mode 0600, git-ignored) for the Britive
# console or ../google-workspace, and is also held in this root's state: protect
# terraform.tfstate as you would the key. Rotate it by tainting the key resource.
# Organisations that enforce iam.disableServiceAccountKeyCreation refuse to create it.

resource "google_service_account_key" "britive" {
  count              = local.wif ? 0 : 1
  service_account_id = google_service_account.britive.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "local_sensitive_file" "key" {
  count                = local.wif ? 0 : 1
  content_base64       = google_service_account_key.britive[0].private_key
  filename             = "${path.module}/keys/key.json"
  file_permission      = "0600"
  directory_permission = "0700"
}
