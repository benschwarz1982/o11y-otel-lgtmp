# Corresponds to README step 1 (az aks create), but with our own VNet instead
# of the default VNet that AKS creates automatically (see networking module).
# Existing finding, not yet assessed - see .trivyignore.yaml's header.
#trivy:ignore:AZU-0041
#trivy:ignore:AZU-0042
#trivy:ignore:AZU-0043
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.cluster_name

  # oidc_issuer_enabled and default_node_pool.upgrade_settings are declared
  # explicitly, because AKS automatically populates these with values on
  # creation (oidc_issuer_enabled=true, upgrade_settings with max_surge=10%),
  # even though we never set them - without an explicit declaration, every
  # subsequent "terraform plan" would show a spurious persistent diff trying
  # to remove these values again.
  oidc_issuer_enabled = true

  # NFR-04 mTLS rollout follow-on (README "Open Points") - moving Tempo off
  # self-hosted MinIO onto native Azure Blob Storage needs Azure AD Workload
  # Identity (the mutating webhook that projects a federated OIDC token into
  # a pod) for its own zero-static-credential auth. oidc_issuer_enabled
  # above is only the token *issuer* - the admission webhook itself is this
  # separate, non-disruptive control-plane feature flag (no node pool
  # changes).
  workload_identity_enabled = true

  # Required as of azurerm provider v5.0 (previously this block didn't
  # exist at all) - mode = "Manual" is the schema's own default and
  # matches this cluster's actual behavior exactly: node pools here are
  # entirely hand-declared (default_node_pool below), never Karpenter-
  # style auto-provisioned. An explicit declaration of an already-true
  # default, same reasoning as oidc_issuer_enabled above.
  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name           = "nodepool1"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = var.vnet_subnet_id

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # G12 (NFR-03): Secrets Store CSI driver + Azure Key Vault provider as
  # AKS add-on. Its managed identity (key_vault_secrets_provider[0].
  # secret_identity) reads the platform Key Vault
  # (terraform/environments/observability-stack, access policy) and
  # mounts secrets straight into pods - no Kubernetes Secret in etcd.
  # Rotation: changed Key Vault values reach the mounted files within 2m.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  network_profile {
    network_plugin = "azure"
    # Enforces NetworkPolicy objects. Found live: without a policy engine
    # (AKS default "none") the openclaw-egress/-ingress policies were
    # created but never enforced - OpenClaw could reach e.g. Mimir on
    # port 80. Calico, not Cilium: policy enforcement only, the Azure
    # data plane and kube-proxy stay as they are - Cilium would replace
    # both, an untested risk for the Linkerd mesh the observability
    # namespace runs in. Azure NPM is retired on Linux on 2028-09-30.
    # In place on an existing cluster (azurerm 5.6.0 ForceNewIfChange
    # only for transitions away from a set policy; "none" is read back
    # as ""), but AKS reimages every node - run deploy:infra in a quiet
    # window, and check build:terraform-plan says "update in-place".
    network_policy = "calico"
    # A dedicated, purely virtual range for K8s service IPs (ClusterIPs) -
    # must lie outside the real VNet address spaces (aks-vnet 10.0.0.0/16,
    # observability-clients-vnet 10.1.0.0/16), otherwise AKS rejects it with
    # "ServiceCidrOverlapExistingSubnetsCidr".
    service_cidr   = "10.2.0.0/16"
    dns_service_ip = "10.2.0.10"
  }
}

# The cluster's own system-assigned identity needs this to provision the
# internal LoadBalancer Service (otel-gateway-internal, see README D1) -
# without it, the Service stays stuck at EXTERNAL-IP <pending> with
# AuthorizationFailed on subnets/read. Every terraform apply that (re)creates
# the cluster gives it a brand-new identity object id, so this can't be a
# one-off manual step (see README's Known Risks - it used to be, and had to
# be redone by hand after every full destroy). skip_service_principal_aad_check
# is required here specifically because the identity was *just* created by
# the azurerm_kubernetes_cluster resource above in the same apply - without
# it, the provider's own pre-flight check that the principal exists in Azure
# AD can run before that creation has replicated, and fails.
#
# This is a plain ARM role assignment (Microsoft.Authorization/roleAssignments)
# on an identity Azure itself already created and manages - unlike the
# azuread_application/azuread_service_principal resources this project
# deliberately avoids (see terraform/README.md and README.md's Known
# Risks), it doesn't go through Microsoft Graph to create a new principal,
# so it isn't affected by this Playground tenant's restricted Graph
# permissions.
resource "azurerm_role_assignment" "aks_identity_network_contributor" {
  scope                            = var.vnet_id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.main.identity[0].principal_id
  skip_service_principal_aad_check = true
}
