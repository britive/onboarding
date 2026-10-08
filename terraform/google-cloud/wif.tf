# integration_type = "wif": the Britive tenant presents an OIDC token to this pool
# and impersonates the service account. No key is ever created.

locals {
  issuer_url = coalesce(var.britive_issuer_url, "${coalesce(var.britive_tenant_url, "https://unset")}/api/auth/sso/oauth2")
}

resource "google_iam_workload_identity_pool" "britive" {
  count = local.wif ? 1 : 0

  project                   = local.project_id
  workload_identity_pool_id = var.workload_identity_pool_id
  display_name              = "Britive"
  description               = "Identities from the Britive tenant"
  depends_on                = [time_sleep.apis]
}

# Default audience (no allowed_audiences) and the two attribute mappings, as
# Britive's prerequisites specify.
resource "google_iam_workload_identity_pool_provider" "britive" {
  count = local.wif ? 1 : 0

  project                            = local.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.britive[0].workload_identity_pool_id
  workload_identity_pool_provider_id = var.workload_identity_provider_id
  display_name                       = "Britive OIDC"

  attribute_mapping = {
    "google.subject"  = "assertion.sub"
    "attribute.email" = "assertion.email"
  }

  oidc {
    issuer_uri = local.issuer_url
  }
}

# Identities in the pool may mint tokens for the service account (Britive's
# documented binding) and act as it through workload identity federation.
resource "google_service_account_iam_member" "pool" {
  for_each = local.wif ? toset(["roles/iam.serviceAccountTokenCreator", "roles/iam.workloadIdentityUser"]) : toset([])

  service_account_id = google_service_account.britive.name
  role               = each.value
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.britive[0].name}/*"
}
