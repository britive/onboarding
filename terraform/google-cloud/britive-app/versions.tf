terraform {
  required_version = ">= 1.5.0"

  required_providers {
    britive = { source = "britive/britive", version = "~> 3.0" }
  }
}

# Tenant and token come from the environment:
#   export BRITIVE_TENANT=https://your-tenant.britive-app.com
#   export BRITIVE_TOKEN=<API token with rights over Applications>
provider "britive" {}
