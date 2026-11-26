terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  # v5.0's default (`none`) stopped automatically registering the ~60
  # Resource Providers earlier provider versions did on init - `legacy`
  # preserves that exact prior behavior explicitly, rather than relying
  # on every RP this subscription needs already being registered from
  # past applies (see the azurerm 5.0 upgrade guide's "Resource
  # Provider Registration Changes").
  resource_provider_registrations = "legacy"

  features {}
}
