terraform {
  required_version = ">= 1.5"

  required_providers {
    britive = {
      source  = "britive/britive"
      version = "~> 3.0"
    }
  }
}

# Credentials from the environment: BRITIVE_TENANT (https://<tenant>.britive-app.com)
# and BRITIVE_TOKEN. Never put the token in a tracked file.
provider "britive" {}
