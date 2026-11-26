# Terraform-managed replacement for scripts/fleet-4015-filestorage.sh /
# instrumentation-4015-filestorage.sh / destroy-fleet-4015-filestorage.sh -
# IaC Roadmap milestone "Terraform for the Kubernetes-native demo apps".
# Real Azure Storage Account + a synthetic Python workload against it,
# deliberately pointed at an inert OTLP endpoint until var.instrument
# flips - see variables.tf.

data "azurerm_kubernetes_cluster" "main" {
  name                = var.aks_cluster_name
  resource_group_name = var.resource_group_name
}

# Deterministic, state-tracked name instead of the old script's
# fresh-random-every-run one (discovered again only by prefix-scanning
# at destroy time) - `terraform destroy` now just deletes the one
# resource in its own state, same as everywhere else in this repo.
resource "random_string" "storage_suffix" {
  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Existing finding, not yet assessed - see .trivyignore.yaml's header.
#trivy:ignore:AZU-0012
resource "azurerm_storage_account" "filestorage" {
  name                     = "stotelddemo${random_string.storage_suffix.result}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"
}

resource "azurerm_storage_container" "demo_files" {
  name = "demo-files"
  # storage_account_name (removed in azurerm provider v5.0) ->
  # storage_account_id, per that version's own upgrade guide.
  storage_account_id    = azurerm_storage_account.filestorage.id
  container_access_type = "private"
}

resource "kubernetes_namespace_v1" "filestorage_demo" {
  metadata {
    name = "filestorage-demo"
  }
}

resource "kubernetes_secret_v1" "filestorage_credentials" {
  metadata {
    name      = "filestorage-credentials"
    namespace = kubernetes_namespace_v1.filestorage_demo.metadata[0].name
  }

  data = {
    STORAGE_ACCOUNT_NAME = azurerm_storage_account.filestorage.name
    STORAGE_ACCOUNT_KEY  = azurerm_storage_account.filestorage.primary_access_key
  }
}

resource "kubernetes_config_map_v1" "filestorage_source" {
  metadata {
    name      = "filestorage-source"
    namespace = kubernetes_namespace_v1.filestorage_demo.metadata[0].name
  }

  # instrumentation/platforms/object-storage/workload.py stays a
  # separate file (not inlined) - it's the canonical reference read
  # directly, same reason as every other *-demo source file this
  # milestone keeps as file().
  data = {
    "workload.py" = file("${path.module}/../../../instrumentation/platforms/object-storage/workload.py")
  }
}

resource "kubernetes_deployment_v1" "filestorage_workload" {
  metadata {
    name      = "filestorage-workload"
    namespace = kubernetes_namespace_v1.filestorage_demo.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "filestorage-workload"
      }
    }

    template {
      metadata {
        labels = {
          app = "filestorage-workload"
        }
      }

      spec {
        container {
          name  = "workload"
          image = "python:3.15.2-slim"

          command = ["sh", "-c", <<-EOT
            pip install --quiet azure-storage-blob \
              opentelemetry-api opentelemetry-sdk \
              opentelemetry-exporter-otlp-proto-http \
              opentelemetry-instrumentation-logging
            python /config/workload.py
          EOT
          ]

          # var.instrument flips this from an inert loopback address to
          # the real gateway - a plain env var change on the Deployment
          # pod template already triggers a rollout on its own, no
          # `kubectl rollout restart`/checksum-annotation trick needed
          # here (unlike fleet-1294-netzwerk-basis's ConfigMap swap).
          env {
            name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
            value = var.instrument ? "http://otel-gateway-collector.observability.svc.cluster.local:4318" : "http://127.0.0.1:4318"
          }
          env {
            name  = "TENANT_ID"
            value = "4015-prod"
          }
          env {
            name  = "STORAGE_CONTAINER"
            value = azurerm_storage_container.demo_files.name
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.filestorage_credentials.metadata[0].name
            }
          }

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
            name       = "source"
            mount_path = "/config"
          }
        }

        volume {
          name = "source"
          config_map {
            name = kubernetes_config_map_v1.filestorage_source.metadata[0].name
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
  from = kubernetes_namespace.filestorage_demo
  to   = kubernetes_namespace_v1.filestorage_demo
}

moved {
  from = kubernetes_secret.filestorage_credentials
  to   = kubernetes_secret_v1.filestorage_credentials
}

moved {
  from = kubernetes_config_map.filestorage_source
  to   = kubernetes_config_map_v1.filestorage_source
}

moved {
  from = kubernetes_deployment.filestorage_workload
  to   = kubernetes_deployment_v1.filestorage_workload
}
