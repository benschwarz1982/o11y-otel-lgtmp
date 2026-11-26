# Terraform-managed replacement for the CRD-instance parts of
# scripts/deploy-collectors.sh (the agent OTel Collector CR) and
# scripts/install-ingress.sh (ClusterIssuer/Certificate/IngressRoute) -
# see ../observability-stack for the Helm releases/RBAC/plain manifests
# that provide the CRDs these resources are instances of, and this
# module's own top-of-file split rationale.
#
# The gateway OpenTelemetryCollector CR (collector-gateway/
# otel-gateway-collector.yaml) deliberately does NOT live here anymore -
# see ../tenants/main.tf's own header comment. It embeds the onboarding
# tenant allowlist (`filter/reject_unknown_tenants`), so it needs to be
# rolled out by `deploy:tenants` (onboarding-scoped), not
# `deploy:observability-stack` (platform-scoped) - otherwise a fresh
# platform deploy would already accept every fixed-fleet tenant's
# telemetry before any of them actually went through onboarding/approval
# (IaC Roadmap milestone, done).
#
# All manifests still here are read straight from their existing YAML
# files (yamldecode(file(...))), not transcribed into HCL.

data "azurerm_kubernetes_cluster" "main" {
  name                = var.aks_cluster_name
  resource_group_name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

locals {
  repo_root = "${path.module}/../../.."
}

# ---------------------------------------------------------------------------
# OTel Collector CRs
# ---------------------------------------------------------------------------

# The node agent CR moved to terraform/environments/tenants
# (null_resource.otel_agent_collector, F20). Forget it here without
# deleting the running DaemonSet - tenants:rollout re-applies it.
removed {
  from = kubernetes_manifest.otel_agent_daemonset

  lifecycle {
    destroy = false
  }
}

# ---------------------------------------------------------------------------
# cert-manager ClusterIssuer + Grafana Certificate/IngressRoute - only
# when a cert-manager Service Principal is actually configured, same
# guard scripts/install-ingress.sh used.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "cluster_issuer_azuredns" {
  count = var.cert_manager_client_id != "" ? 1 : 0

  manifest = yamldecode(templatefile("${local.repo_root}/k8s/ingress/cluster-issuer-azuredns.yaml", {
    cert_manager_client_id = var.cert_manager_client_id
    azure_subscription_id  = data.azurerm_client_config.current.subscription_id
    azure_tenant_id        = data.azurerm_client_config.current.tenant_id
    azure_resource_group   = var.resource_group_name
  }))
}

# ---------------------------------------------------------------------------
# Internal CA (NFR-04 mTLS rollout, Phase 1 - README "Open Points") - a
# second, self-signed ClusterIssuer, entirely separate from the ACME one
# above. No count guard: unlike the ACME issuer, this one needs no Azure
# Service Principal - it's a self-signed root Terraform generates itself,
# always safe to create.
# ---------------------------------------------------------------------------

resource "tls_private_key" "internal_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "internal_ca" {
  private_key_pem       = tls_private_key.internal_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600 # 10 years - a root CA, not meant to rotate often
  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "key_encipherment",
    "digital_signature",
  ]
  subject {
    common_name  = "observability-otel-demo Internal CA"
    organization = "observability-otel-demo"
  }
}

# cert-manager's own required shape for a ClusterIssuer of kind "ca" -
# the secret it signs FROM, not a Certificate it issues. Lives in the
# cert-manager namespace (its own default --cluster-resource-namespace,
# unmodified by this repo's helm_release.cert_manager).
resource "kubernetes_secret_v1" "internal_ca" {
  metadata {
    name      = "internal-ca-key-pair"
    namespace = "cert-manager"
  }
  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = tls_self_signed_cert.internal_ca.cert_pem
    "tls.key" = tls_private_key.internal_ca.private_key_pem
  }
}

resource "kubernetes_manifest" "cluster_issuer_internal_ca" {
  manifest   = yamldecode(file("${local.repo_root}/k8s/ingress/cluster-issuer-internal-ca.yaml"))
  depends_on = [kubernetes_secret_v1.internal_ca]
}

# NFR-04 mTLS rollout, Phase 3 (README "Open Points") - the Gateway's
# OWN TLS identity for its per-tenant otlp/tenant-<id> receivers
# (collector-gateway/otel-gateway-collector.yaml, wired in by
# scripts/provision.py's update_gateway_tenant_mtls_receivers()). One
# shared server cert for every tenant receiver - only the CLIENT
# ca_file differs per tenant (Phase 2's own per-tenant Certificates).
#
# DNS names: the in-cluster Service names plus *.otlp.internal - the SNI
# every VM collector sends (server_name_override "<tenant_id>.otlp.internal",
# which Traefik's per-tenant IngressRouteTCP routes on and passes through
# unterminated). The VM collectors verify this certificate against the
# internal root CA (ca_file, F08) under exactly that name, so neither the
# load balancer's dynamic private IP nor insecure_skip_verify is needed.
resource "kubernetes_manifest" "otel_gateway_server_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "otel-gateway-server"
      namespace = "observability"
    }
    spec = {
      secretName = "otel-gateway-server-cert"
      issuerRef  = { name = "internal-ca", kind = "ClusterIssuer" }
      commonName = "otel-gateway-internal.observability.svc"
      dnsNames = [
        "otel-gateway-internal.observability.svc",
        "otel-gateway-internal.observability.svc.cluster.local",
        "*.otlp.internal",
      ]
      usages      = ["server auth"]
      duration    = "2160h"
      renewBefore = "360h"
    }
  }
  depends_on = [kubernetes_manifest.cluster_issuer_internal_ca]
}

resource "kubernetes_manifest" "grafana_cert" {
  count = var.cert_manager_client_id != "" ? 1 : 0

  manifest   = yamldecode(file("${local.repo_root}/k8s/ingress/grafana-cert.yaml"))
  depends_on = [kubernetes_manifest.cluster_issuer_azuredns]
}

resource "kubernetes_manifest" "grafana_ingressroute" {
  count = var.cert_manager_client_id != "" ? 1 : 0

  manifest   = yamldecode(file("${local.repo_root}/k8s/ingress/grafana-ingressroute.yaml"))
  depends_on = [kubernetes_manifest.grafana_cert]
}

# ---------------------------------------------------------------------------
# Linkerd (NFR-04 mTLS rollout, Phase 4 - README "Open Points") - automatic
# mTLS for internal-cluster hops (Gateway<->Backends, backend-ring,
# and Grafana's own query-path to those same backends -
# anything pod-to-pod inside the meshed `observability` namespace).
# Transparent at the proxy layer: no application config changes anywhere -
# Grafana's datasources/the Gateway's exporters keep their existing
# `http://` URLs unchanged, same as every service mesh's whole point.
#
# Trust chained under the same shared internal-ca root as the OTLP
# client-cert PKI (Phases 1-3) via a dedicated intermediate - one
# auditable root for the platform's internal trust, purpose-scoped
# intermediates below it (same pattern as Phase 2's per-tenant
# intermediates, just one fixed intermediate here instead of per-tenant).
# CNs/validity match Linkerd's own documented convention for manually
# generated certs (linkerd.io/2-edge/tasks/generate-certificates/) even
# though cert-manager, not `step`, issues them here.
# ---------------------------------------------------------------------------

resource "helm_release" "linkerd_crds" {
  name             = "linkerd-crds"
  repository       = "https://helm.linkerd.io/stable"
  chart            = "linkerd-crds"
  version          = "1.8.0"
  namespace        = "linkerd"
  create_namespace = true
}

# This module has no ambient kubeconfig (see this module's own
# versions.tf comment) - its own kubeconfig, generated from the same
# azurerm_kubernetes_cluster data source the kubernetes/helm providers
# already use, same idiom as ../observability-stack's own
# null_resource.mimir_webhook_cleanup / ../tenants' own
# null_resource.otel_gateway_collector. Needed by the two null_resources below
# (waiting for the trust anchor to actually be issued, and the final
# mesh-wide pod rollout).
resource "local_sensitive_file" "kubeconfig" {
  content  = data.azurerm_kubernetes_cluster.main.kube_config_raw
  filename = "${path.module}/.terraform-kubeconfig"
}

# The root of Linkerd's OWN mesh identity - deliberately NOT the same
# intermediate Phase 2 issues per onboarded tenant (different trust
# domain, different purpose: this one is for in-cluster pod identity,
# not external OTLP client authentication).
resource "kubernetes_manifest" "linkerd_trust_anchor" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "linkerd-trust-anchor"
      namespace = "linkerd"
    }
    spec = {
      isCA        = true
      secretName  = "linkerd-trust-anchor"
      issuerRef   = { name = "internal-ca", kind = "ClusterIssuer" }
      commonName  = "root.linkerd.cluster.local"
      privateKey  = { algorithm = "ECDSA", size = 256 }
      usages      = ["cert sign", "crl sign", "digital signature", "key encipherment"]
      duration    = "87600h" # 10 years - Linkerd's own documented convention for this cert
      renewBefore = "720h"
    }
  }
  depends_on = [helm_release.linkerd_crds, kubernetes_manifest.cluster_issuer_internal_ca]
}

# kubernetes_manifest only waits for the API server to ACCEPT the
# Certificate object, not for cert-manager to actually issue it and
# populate its Secret - found live: the data source below read the
# Secret before cert-manager had filled in its `data`, getting back
# null and failing with "Attempt to index null value". Waits for the
# Certificate's own Ready condition, the same signal cert-manager
# itself uses to mean "the Secret's data is actually populated now".
resource "null_resource" "wait_for_linkerd_trust_anchor" {
  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local_sensitive_file.kubeconfig.filename
    }
    command = "kubectl wait --for=condition=Ready certificate/linkerd-trust-anchor -n linkerd --timeout=60s"
  }
  depends_on = [kubernetes_manifest.linkerd_trust_anchor, local_sensitive_file.kubeconfig]
}

resource "kubernetes_manifest" "linkerd_trust_anchor_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "linkerd-trust-anchor-issuer"
      namespace = "linkerd"
    }
    spec = {
      ca = { secretName = "linkerd-trust-anchor" }
    }
  }
  depends_on = [kubernetes_manifest.linkerd_trust_anchor]
}

# The actual signing cert Linkerd's identity service holds and uses to
# mint short-lived per-pod certs on the fly. secretName is EXACTLY
# "linkerd-identity-issuer" - the control plane's own expected Secret
# name in externalCA mode (identity.externalCA=true below) - so
# cert-manager renews this Secret IN PLACE and Linkerd's identity
# service hot-reloads it automatically, no control-plane restart needed
# on renewal (unlike the trust anchor above, which the mesh only ever
# reads once at install time).
resource "kubernetes_manifest" "linkerd_identity_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "linkerd-identity-issuer"
      namespace = "linkerd"
    }
    spec = {
      isCA        = true
      secretName  = "linkerd-identity-issuer"
      issuerRef   = { name = "linkerd-trust-anchor-issuer", kind = "Issuer" }
      commonName  = "identity.linkerd.cluster.local"
      privateKey  = { algorithm = "ECDSA", size = 256 }
      usages      = ["cert sign", "crl sign", "digital signature", "key encipherment"]
      duration    = "8760h" # 1 year - Linkerd's own documented convention for this cert
      renewBefore = "720h"
    }
  }
  depends_on = [kubernetes_manifest.linkerd_trust_anchor_issuer]
}

# Same race as wait_for_linkerd_trust_anchor above - the control plane's
# own pods would otherwise start before cert-manager has actually
# populated this Secret, crash-looping until it catches up.
resource "null_resource" "wait_for_linkerd_identity_issuer" {
  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local_sensitive_file.kubeconfig.filename
    }
    command = "kubectl wait --for=condition=Ready certificate/linkerd-identity-issuer -n linkerd --timeout=60s"
  }
  depends_on = [kubernetes_manifest.linkerd_identity_issuer, local_sensitive_file.kubeconfig]
}

data "kubernetes_secret_v1" "linkerd_trust_anchor" {
  metadata {
    name      = "linkerd-trust-anchor"
    namespace = "linkerd"
  }
  depends_on = [null_resource.wait_for_linkerd_trust_anchor]
}

# identity.externalCA=true (below) means the chart does NOT create this
# ConfigMap itself - that's normally trust-manager's job (a separate
# Jetstack controller for exactly this, not installed here to keep this
# rollout self-contained). Every meshed proxy (including the control
# plane's own self-injected ones) mounts it at
# /var/run/linkerd/identity/trust-roots/ - found live: without it,
# linkerd-identity's own pod never leaves Init:0/1 ("configmap
# linkerd-identity-trust-roots not found") and every already-meshed
# pod's proxy container fails with CreateContainerConfigError. Key name
# (ca-bundle.crt) is Linkerd's own fixed convention, not configurable.
# A static Terraform-managed copy is fine here, same reasoning as the
# trust anchor Secret it's sourced from - the root doesn't need live
# rotation-watching the way the issuer cert does.
resource "kubernetes_config_map_v1" "linkerd_identity_trust_roots" {
  metadata {
    name      = "linkerd-identity-trust-roots"
    namespace = "linkerd"
  }
  data = {
    "ca-bundle.crt" = data.kubernetes_secret_v1.linkerd_trust_anchor.data["tls.crt"]
  }
}

resource "helm_release" "linkerd_control_plane" {
  name       = "linkerd-control-plane"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd-control-plane"
  version    = "1.16.11"
  namespace  = "linkerd"

  set_sensitive = [
    { name = "identityTrustAnchorsPEM", value = data.kubernetes_secret_v1.linkerd_trust_anchor.data["tls.crt"] },
  ]
  set = [
    { name = "identity.externalCA", value = "true" },
    { name = "identity.issuer.scheme", value = "kubernetes.io/tls" },
  ]

  depends_on = [null_resource.wait_for_linkerd_identity_issuer, kubernetes_config_map_v1.linkerd_identity_trust_roots]
}

resource "helm_release" "linkerd_viz" {
  name             = "linkerd-viz"
  repository       = "https://helm.linkerd.io/stable"
  chart            = "linkerd-viz"
  version          = "30.12.11"
  namespace        = "linkerd-viz"
  create_namespace = true

  depends_on = [helm_release.linkerd_control_plane]
}

# The `observability` namespace's own linkerd.io/inject annotation
# (terraform/environments/observability-stack/main.tf's
# kubernetes_namespace_v1.observability) only takes effect for pods
# CREATED after it's set - existing Deployments/StatefulSets/DaemonSets
# need a rollout to actually pick up the sidecar.
resource "null_resource" "linkerd_mesh_rollout" {
  triggers = {
    linkerd_control_plane_revision = helm_release.linkerd_control_plane.metadata.revision
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local_sensitive_file.kubeconfig.filename
    }
    # `rollout status` errors outright ("rollout status is only available
    # for RollingUpdate strategy type") for any StatefulSet using
    # OnDelete instead - found live: Mimir's own zone-aware ingester/
    # store-gateway StatefulSets use exactly that (Grafana's own
    # mimir-rollout-operator handles their actual pod cycling instead of
    # the native StatefulSet controller), which made the combined
    # multi-type status command fail even though `rollout restart` had
    # already triggered a real, verified-live restart (new pods,
    # confirmed carrying the linkerd-proxy sidecar) for every one of
    # them. Deployments/DaemonSets all use RollingUpdate here, so the
    # combined command stays for those; StatefulSets are checked
    # individually, skipping (not failing) the ones kubectl can't watch
    # this way.
    command = <<-EOT
      set -e
      kubectl rollout restart deployment,statefulset,daemonset -n observability
      kubectl rollout status deployment,daemonset -n observability --timeout=600s
      for sts in $(kubectl get statefulset -n observability -o jsonpath='{.items[*].metadata.name}'); do
        strategy=$(kubectl get statefulset "$sts" -n observability -o jsonpath='{.spec.updateStrategy.type}')
        if [ "$strategy" = "RollingUpdate" ]; then
          kubectl rollout status "statefulset/$sts" -n observability --timeout=600s
        else
          echo "Skipping rollout status for statefulset/$sts (updateStrategy=$strategy, not watchable via kubectl rollout status)"
        fi
      done
    EOT
  }

  depends_on = [helm_release.linkerd_control_plane, local_sensitive_file.kubeconfig]
}
