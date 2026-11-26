terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # Storage account name uniqueness suffix (MinIO -> Azure Blob Storage
    # migration, README "Open Points") - same idiom as the admin password
    # generation elsewhere in this repo's Terraform.
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

  features {
    # G12: the Key Vault has soft delete (7 days) but no purge
    # protection. No purge on destroy: the pipeline identities only have
    # resource-group scope and purging needs a subscription-level action
    # (Microsoft.KeyVault/locations/deletedVaults/purge/action). The
    # deleted vault expires after 7 days; a rebuild gets a new name (new
    # random suffix), so the soft-deleted one never blocks it.
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

# Auth for both providers comes from the AKS data source's own kube_config
# (client cert/key, cluster CA) - the cluster has no
# azure_active_directory_role_based_access_control block (see
# terraform/modules/aks-cluster/main.tf), so local-account credentials
# work directly. Deliberately not `az aks get-credentials`/a kubeconfig
# file - this is the same Service Principal (ARM_* env vars) the azurerm
# provider above already uses, so no extra CI tooling/auth step is needed.
provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.main.kube_config.0.host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = data.azurerm_kubernetes_cluster.main.kube_config.0.host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
  }
}
