# Terraform-managed replacement for scripts/fleet-1294-netzwerk-basis.sh /
# instrumentation-1294-netzwerk-basis.sh / destroy-fleet-1294-netzwerk-basis.sh -
# IaC Roadmap milestone "Terraform for the Kubernetes-native demo apps".
# SNMP simulator (a real snmpd, its config inlined in the "snmpd"
# container's command below, queried over real SNMP by the snmp
# receiver in instrumentation/platforms/1294-netzwerk-basis/*.yaml - unlike
# fleet-4015-filestorage's workload.py, nothing here fabricates
# metrics directly; only the fact that this snmpd runs in a container
# instead of on a real switch is simulated) + its dedicated OTel
# collector sidecar.
#
# var.instrument toggles which collector config the sidecar runs -
# preserves the existing "provision without telemetry, then instrument"
# two-step Demo Runbook choreography (see variables.tf) instead of
# collapsing to always-instrumented.

data "azurerm_kubernetes_cluster" "main" {
  name                = var.aks_cluster_name
  resource_group_name = var.resource_group_name
}

resource "kubernetes_namespace_v1" "netzwerk_demo" {
  metadata {
    name = "netzwerk-demo"
  }
}

resource "kubernetes_config_map_v1" "snmp_collector_config" {
  metadata {
    name      = "snmp-collector-config"
    namespace = kubernetes_namespace_v1.netzwerk_demo.metadata[0].name
  }

  # Two variants of instrumentation/platforms/1294-netzwerk-basis/*.yaml,
  # kept as separate files (not inlined) so they stay the canonical
  # reference for anyone reading the collector config directly - see
  # each file's own header comment for what the bare vs. instrumented
  # variant does.
  data = {
    "config.yaml" = var.instrument ? file("${path.module}/../../../instrumentation/platforms/1294-netzwerk-basis/config.yaml") : file("${path.module}/../../../instrumentation/platforms/1294-netzwerk-basis/config-bare.yaml")
  }
}

resource "kubernetes_deployment_v1" "snmp_device" {
  metadata {
    name      = "snmp-device"
    namespace = kubernetes_namespace_v1.netzwerk_demo.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "snmp-device"
      }
    }

    template {
      metadata {
        labels = {
          app = "snmp-device"
        }
        annotations = {
          # kubernetes_config_map doesn't trigger a Deployment rollout
          # on its own - unlike the old script's explicit `kubectl
          # rollout restart`, this annotation changes whenever the
          # config content changes, forcing one.
          "checksum/config" = sha256(kubernetes_config_map_v1.snmp_collector_config.data["config.yaml"])
        }
      }

      spec {
        container {
          name  = "snmpd"
          image = "debian:13-slim"

          command = ["sh", "-c", <<-EOT
            set -eu
            apt-get update -qq
            apt-get install -y -qq --no-install-recommends snmpd >/dev/null
            cat > /etc/snmp/snmpd.conf <<'EOF'
            rocommunity public
            syslocation "Demo Netzwerk Basis (1294)"
            syscontact platform-team@example.com
            EOF
            exec /usr/sbin/snmpd -f -Lo -c /etc/snmp/snmpd.conf
          EOT
          ]

          # The limit covers the apt-get install at container start
          # (Debian 13's apt peaks above 128Mi); snmpd itself needs a few Mi.
          resources {
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              memory = "256Mi"
            }
          }
        }

        container {
          name  = "otel-collector"
          image = "otel/opentelemetry-collector-contrib:0.166.0"

          args = ["--config=/etc/otelcol-contrib/config.yaml"]

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/otelcol-contrib"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.snmp_collector_config.metadata[0].name
          }
        }
      }
    }
  }
}

# moved blocks for the kubernetes provider v3 rename -
# unversioned resource types deprecated in favour of _v1 (see
# the provider's own v3.0.0 CHANGELOG) - required so Terraform
# treats this as a rename of the same live object, not a
# destroy+recreate.
moved {
  from = kubernetes_namespace.netzwerk_demo
  to   = kubernetes_namespace_v1.netzwerk_demo
}

moved {
  from = kubernetes_config_map.snmp_collector_config
  to   = kubernetes_config_map_v1.snmp_collector_config
}

moved {
  from = kubernetes_deployment.snmp_device
  to   = kubernetes_deployment_v1.snmp_device
}
