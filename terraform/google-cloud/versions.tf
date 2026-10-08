terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = { source = "hashicorp/google", version = "~> 8.0" }
    local  = { source = "hashicorp/local", version = "~> 2.5" }
    time   = { source = "hashicorp/time", version = "~> 0.13" }
  }
}

# Credentials come from Application Default Credentials:
#   gcloud auth application-default login
provider "google" {}
