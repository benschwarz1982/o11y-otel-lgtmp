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
    # Generates the internal root CA (NFR-04 mTLS rollout, Phase 1) -
    # tls_private_key/tls_self_signed_cert, same idiom this repo already
    # uses for SSH keys (terraform/environments/aiops/main.tf's
    # tls_private_key.openclaw_ssh), applied to a CA cert instead.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # local_sensitive_file.kubeconfig (NFR-04 mTLS rollout, Phase 4) -
    # this module's own kubeconfig for null_resource.linkerd_mesh_rollout's
    # kubectl calls, same idiom as ../observability-stack's own
    # null_resource.mimir_webhook_cleanup and ../tenants' null_resource.
    # otel_gateway_collector. Was unused here for a while (the original resource
    # this pin existed for moved to ../tenants) - real use again now.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    # linkerd-crds/linkerd-control-plane/linkerd-viz (NFR-04 mTLS rollout,
    # Phase 4) - same version pin as ../observability-stack's own helm
    # provider.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    # null_resource.linkerd_mesh_rollout - same version pin as
    # ../observability-stack's own null provider.
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
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

# Same auth approach as ../observability-stack - see that module's
# versions.tf for why (no azure_active_directory_role_based_access_control
# block on this cluster, so local-account kube_config credentials work).
# This module's kubernetes_manifest resources need the CRDs that module
# installs (OTel Operator, cert-manager, Traefik Helm releases) to already
# exist in the live cluster before this one can be planned - hence the
# split into two states, applied in sequence. See its own README section
# and .gitlab-ci.yml for the apply order.
provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.main.kube_config.0.host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
}

# NFR-04 mTLS rollout, Phase 4 - linkerd-crds/linkerd-control-plane/
# linkerd-viz. Same auth approach as the kubernetes provider above.
provider "helm" {
  kubernetes = {
    host                   = data.azurerm_kubernetes_cluster.main.kube_config.0.host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
  }
}
