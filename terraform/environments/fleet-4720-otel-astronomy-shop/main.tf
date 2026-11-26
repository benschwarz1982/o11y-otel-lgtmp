# Terraform-managed replacement for scripts/fleet-4720-otel-astronomy-shop.sh /
# instrumentation-4720-otel-astronomy-shop.sh /
# destroy-fleet-4720-otel-astronomy-shop.sh - IaC Roadmap milestone
# "Terraform for the Kubernetes-native demo apps". The official
# OpenTelemetry Astronomy Shop Demo chart, plus public ingress
# (astronomy-shop.<dns-zone>).

data "azurerm_kubernetes_cluster" "main" {
  name                = var.aks_cluster_name
  resource_group_name = var.resource_group_name
}

data "azurerm_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = var.resource_group_name
}

resource "kubernetes_namespace_v1" "astronomy_shop" {
  metadata {
    name = "astronomy-shop"
  }
}

# helm/values/otel-demo-values.yaml/instrumentation/applications/
# otel-astronomy-shop/values-instrument.yaml stay separate files (not
# inlined) - the canonical reference, same reason as every other
# *-demo source file this milestone keeps as file(). The chart version
# is pinned here (0.41.0, current at implementation time) - the old
# script's `helm upgrade --install` had no --version at all.
# The OpenTelemetry Demo chart does not support in-place upgrades
# ("delete the existing release and then install the new version",
# charts/opentelemetry-demo/UPGRADING.md) - a version change replaces
# the release. The namespace (and its certificate/DNS) stays.
locals {
  astronomy_shop_chart_version = "0.42.8"
}

resource "terraform_data" "astronomy_shop_chart_version" {
  input = local.astronomy_shop_chart_version
}

resource "helm_release" "astronomy_shop" {
  name       = "astronomy-shop"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-demo"
  version    = local.astronomy_shop_chart_version
  namespace  = kubernetes_namespace_v1.astronomy_shop.metadata[0].name

  # var.instrument layers values-instrument.yaml's envOverrides on top
  # of the base otel-demo-values.yaml - replaces the old two-step
  # `helm upgrade --install` then `helm upgrade --reuse-values -f
  # values-instrument.yaml`; Helm merges a values list in order, same
  # effect as --reuse-values + an extra -f.
  values = var.instrument ? [
    file("${path.module}/../../../helm/values/otel-demo-values.yaml"),
    file("${path.module}/../../../instrumentation/applications/4720-otel-astronomy-shop/values-instrument.yaml"),
    ] : [
    file("${path.module}/../../../helm/values/otel-demo-values.yaml"),
  ]

  lifecycle {
    replace_triggered_by = [terraform_data.astronomy_shop_chart_version]
  }
}

# ---------------------------------------------------------------------------
# Public ingress (astronomy-shop.<dns-zone>) - same pattern as
# fleet-4139-postgresql's kundenverwaltung.<dns-zone> (see that
# environment's own comment for why no time_sleep is needed here -
# Traefik already exists by the time this job runs).
# ---------------------------------------------------------------------------

data "kubernetes_service_v1" "traefik" {
  metadata {
    name      = "traefik"
    namespace = "ingress-traefik"
  }
}

resource "azurerm_dns_a_record" "astronomy_shop" {
  name                = "astronomy-shop"
  zone_name           = data.azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip]
}

# CRD instances, no typed provider resource - kubernetes_manifest +
# yamldecode(file(...)), same well-typed-schema pattern already
# live-tested for Grafana's own cert/ingressroute in
# observability-stack-crs.
resource "kubernetes_manifest" "astronomy_shop_cert" {
  manifest = yamldecode(templatefile("${path.module}/../../../k8s/ingress/astronomy-shop-cert.yaml", { dns_zone_name = var.dns_zone_name }))
}

resource "kubernetes_manifest" "astronomy_shop_ingressroute" {
  manifest   = yamldecode(templatefile("${path.module}/../../../k8s/ingress/astronomy-shop-ingressroute.yaml", { dns_zone_name = var.dns_zone_name }))
  depends_on = [kubernetes_manifest.astronomy_shop_cert]
}

# moved blocks for the kubernetes provider v3 rename -
# unversioned resource types deprecated in favour of _v1 (see
# the provider's own v3.0.0 CHANGELOG) - required so Terraform
# treats this as a rename of the same live object, not a
# destroy+recreate.
moved {
  from = kubernetes_namespace.astronomy_shop
  to   = kubernetes_namespace_v1.astronomy_shop
}
