terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Archived by HashiCorp on 30 June 2025: still works, receives no fixes. Pinned to
    # its last release.
    googleworkspace = { source = "hashicorp/googleworkspace", version = "0.7.0" }
    random          = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
