terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azuread = { source = "hashicorp/azuread", version = "~> 3.0" }
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}

# Credentials come from `az login` (or the ARM_* environment variables). The
# signed-in identity needs to create app registrations and grant admin consent
# (Global Administrator, or Application Administrator plus Privileged Role
# Administrator) and to assign roles at the Tenant Root Group (User Access
# Administrator there, obtained with "Elevate access"; see the README).
provider "azuread" {}

provider "azurerm" {
  features {}

  # Nothing here is subscription-scoped, but the provider needs a subscription
  # to initialise. ARM_SUBSCRIPTION_ID works too.
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}
