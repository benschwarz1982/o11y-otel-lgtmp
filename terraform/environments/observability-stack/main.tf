# Terraform-managed replacement for scripts/install.sh, scripts/
# deploy-collectors.sh (RBAC part only - the OTel Collector CRs
# themselves live in ../observability-stack-crs, see that module's own
# comment for why), scripts/install-ingress.sh (Helm releases + secret
# only - ClusterIssuer/Certificate/IngressRoute are CRD instances, also
# in ../observability-stack-crs), and scripts/setup-gateway-internal.sh
# (Service only - the redundant `az role assignment create` for Network
# Contributor on aks-vnet is dropped here, not migrated: it duplicates
# terraform/modules/aks-cluster/main.tf's own
# azurerm_role_assignment.aks_identity_network_contributor, already
# fixed there, see README Known Pitfalls).

data "azurerm_kubernetes_cluster" "main" {
  name                = var.aks_cluster_name
  resource_group_name = var.resource_group_name
}

data "azurerm_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = var.resource_group_name
}

resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = "observability"
    # NFR-04 mTLS rollout, Phase 4 (README "Open Points") - Linkerd's
    # mutating webhook injects its proxy sidecar into every pod created
    # in an annotated namespace. Only affects NEW pods - existing
    # Deployments/StatefulSets/DaemonSets need their own rollout to pick
    # it up, handled by terraform/environments/observability-stack-crs's
    # own null_resource.linkerd_mesh_rollout (after Linkerd's control
    # plane, installed in that same module, is actually up).
    annotations = {
      "linkerd.io/inject" = "enabled"
    }
  }
}

resource "kubernetes_namespace_v1" "otel_operator" {
  metadata {
    name = "opentelemetry-operator-system"
  }
}

# ---------------------------------------------------------------------------
# LGTM stack
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Azure Blob Storage (replaces self-hosted MinIO) - Mimir/Loki/Tempo/
# Pyroscope's object storage backend. Found live: MinIO Inc. has withdrawn
# anonymous pull access to its own container images on BOTH quay.io and
# Docker Hub entirely (every tag, including "latest", returns 401 - not a
# stale/retired single tag, the whole public registry access was pulled).
# The old MinIO pod kept running fine since it never needed to re-pull,
# but any restart (a node drain, this repo's own Linkerd mesh rollout,
# anything) would leave it unable to come back. Rather than chase a still-
# pullable mirror (MinIO could withdraw that too), this moves off self-
# hosted MinIO entirely onto the object storage the underlying cloud
# already provides natively - removes an entire stateful service (its own
# image supply chain, PVC, backup/restore concerns) this repo never
# actually needed once running on Azure.
#
# Auth: Tempo supports Azure AD Workload Identity (federated OIDC tokens) -
# confirmed via Grafana's own docs. Loki's chart also exposes a
# useFederatedToken field under storage.azure - trusted here since it's a
# first-class chart value the chart authors added deliberately, not
# something guessed into freeform config. Mimir and Pyroscope's Azure Blob
# clients do NOT support federated tokens - a documented, open limitation
# for Mimir (grafana/mimir#5505, #7447), and Pyroscope's own config
# reference doesn't document an equivalent field either (this repo has
# already been burned once by guessing at an unverified freeform
# structuredConfig key - see pyroscope-values.yaml's own header comment,
# not repeating that here). Those two get the storage account's access
# key via set_sensitive instead - never written to a checked-in
# values.yaml file.
# ---------------------------------------------------------------------------

resource "random_id" "storage_account_suffix" {
  byte_length = 4
}

# Existing finding, not yet assessed - see .trivyignore.yaml's header.
#trivy:ignore:AZU-0012
resource "azurerm_storage_account" "observability" {
  name                     = "stobsotdemo${random_id.storage_account_suffix.hex}"
  resource_group_name      = var.resource_group_name
  location                 = data.azurerm_kubernetes_cluster.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  # Mimir's own docs: hierarchical namespace must stay disabled, or
  # deleted blocks leave behind empty directory placeholders it can never
  # clean up. Also this resource's own schema default - explicit here so
  # the requirement is documented, not just implicitly satisfied.
  is_hns_enabled = false

  # G11 (NFR-14): protection against accidental or malicious deletion.
  # Versioning keeps every overwritten/deleted blob as a version (old
  # versions are removed by the lifecycle policy below), soft delete
  # keeps deleted blobs and containers restorable for 7 days. No
  # immutability policy on these containers: the compactors of Mimir/
  # Loki/Tempo/Pyroscope must delete blocks to enforce retention
  # (NFR-15) - a WORM policy would break exactly that. Restore and
  # legal-hold procedure: README "Backup, Restore and Deletion".
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
}

# G10 (FR-17): hot/cool tiering. Blocks/chunks that have not been
# modified for 7 days move to the Cool tier (online, same read latency,
# lower storage price, higher access price) - recent data, which almost
# every query and dashboard reads, stays Hot. Small, frequently rewritten
# objects (bucket indexes, metastore files) never reach 7 days unmodified
# and stay Hot automatically. Ruler/admin containers are excluded.
# Old blob versions (G11) are deleted after 7 days, so versioning does
# not keep every compactor rewrite forever.
resource "azurerm_storage_management_policy" "observability" {
  storage_account_id = azurerm_storage_account.observability.id

  rule {
    name    = "tier-telemetry-to-cool"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["mimir-blocks/", "loki-chunks/", "tempo-traces/", "pyroscope-data/"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 7
      }
    }
  }

  rule {
    name    = "expire-old-versions"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      version {
        delete_after_days_since_creation = 7
      }
    }
  }
}

locals {
  observability_storage_containers = toset([
    "mimir-blocks", "mimir-ruler", "loki-chunks", "loki-ruler", "loki-admin",
    "tempo-traces", "pyroscope-data",
  ])
}

resource "azurerm_storage_container" "observability" {
  for_each              = local.observability_storage_containers
  name                  = each.value
  storage_account_id    = azurerm_storage_account.observability.id
  container_access_type = "private"
}

# Workload Identity for Tempo/Loki was designed and briefly applied here,
# then reverted - found live: this subscription is a restricted
# "Playground" sandbox (README's own Known Pitfalls) whose deploying
# Service Principal can create the storage account/identities/federated
# credentials but is explicitly denied Microsoft.Authorization/
# roleAssignments/write on ANY scope ("AuthorizationFailed... or the
# scope is invalid"). Without that role assignment the identity
# authenticates to Azure AD fine but gets Forbidden on the actual blob
# read/write - non-functional in this environment specifically, not a
# config mistake. All four backends use the storage account's access key
# via set_sensitive instead - one consistent auth story across Mimir/
# Loki/Tempo/Pyroscope, still never written to a checked-in values.yaml
# file.

# Per-tenant ingestion limits (helm/values/*-tenant-overrides.yaml,
# generated by scripts/provision.py) are part of every LGTM release's
# values here, not only layered on by tenants:rollout's `helm upgrade
# --reuse-values`. Before, this state installed the charts with base
# values only, so any later apply of it (e.g. after a mimir-values.yaml
# change) reset every tenant's limits to the chart defaults until the
# next tenants:rollout. tenants:rollout keeps its own upgrade (it needs
# --reuse-values for the storage keys set below), now with identical
# content. An offboarded tenant's limits linger in the rollout path
# until this state is applied again - harmless, the gateway no longer
# admits that tenant.

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "loki"
  version    = "21.6.0"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  values = [
    file("${path.module}/../../../helm/values/loki-values.yaml"),
    # Per-tenant limits from scripts/provision.py - see the comment
    # above helm_release.loki.
    file("${path.module}/../../../helm/values/loki-tenant-overrides.yaml"),
  ]
  # Chart default (300s) isn't enough for this many components (10+:
  # distributor, ingester, querier, query-frontend, query-scheduler,
  # index-gateway, compactor, gateway, chunks-cache, results-cache) plus
  # Linkerd's own per-pod proxy startup overhead (NFR-04 mTLS rollout,
  # Phase 4) - found live: the actual rollout succeeded (confirmed via
  # the ingester's own logs uploading index tables to Azure Blob
  # Storage) shortly after Terraform's client-side wait already gave up
  # and marked the release "failed".
  timeout = 600

  set = [
    { name = "loki.storage.azure.accountName", value = azurerm_storage_account.observability.name },
  ]
  set_sensitive = [
    { name = "loki.storage.azure.accountKey", value = azurerm_storage_account.observability.primary_access_key },
  ]

  depends_on = [azurerm_storage_container.observability, null_resource.chart_statefulset_migrate]
}

# ---------------------------------------------------------------------------
# Tempo 3 write path: distributors write spans to Kafka, block-builder and
# live-store consume them (helm/values/tempo-values.yaml, ingest.kafka).
# The tempo-distributed chart bundles no broker. A single-node KRaft
# broker (combined broker+controller), same image and setup as the one the
# mimir-distributed chart runs for Mimir - kept separate from it on
# purpose, so Mimir and Tempo don't share one failure point. No
# replication (one broker, replication factor 1): a lost PVC loses only
# spans not yet written to blob storage. Unauthenticated PLAINTEXT like
# Mimir's - reachable only from this namespace (observability_backends
# network policy below).
# ---------------------------------------------------------------------------
resource "random_id" "tempo_kafka_cluster_id" {
  byte_length = 16
}

resource "kubernetes_service_v1" "tempo_kafka_headless" {
  metadata {
    name      = "tempo-kafka-headless"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  spec {
    cluster_ip                  = "None"
    publish_not_ready_addresses = true
    selector = {
      "app.kubernetes.io/name" = "tempo-kafka"
    }
    port {
      name        = "kafka"
      port        = 9092
      target_port = "kafka"
    }
    port {
      name        = "controller"
      port        = 9093
      target_port = "controller"
    }
  }
}

resource "kubernetes_service_v1" "tempo_kafka" {
  metadata {
    name      = "tempo-kafka"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "tempo-kafka"
    }
    port {
      name        = "kafka"
      port        = 9092
      target_port = "kafka"
    }
  }
}

resource "kubernetes_stateful_set_v1" "tempo_kafka" {
  metadata {
    name      = "tempo-kafka"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "tempo-kafka"
    }
  }
  spec {
    service_name = kubernetes_service_v1.tempo_kafka_headless.metadata[0].name
    replicas     = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "tempo-kafka"
      }
    }
    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "tempo-kafka"
        }
      }
      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 1001
          run_as_group    = 1001
          fs_group        = 1001
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name  = "kafka"
          image = "docker.io/apache/kafka-native:4.4.0"
          port {
            name           = "kafka"
            container_port = 9092
          }
          port {
            name           = "controller"
            container_port = 9093
          }
          env {
            # CLUSTER_ID, not KAFKA_CLUSTER_ID: the apache/kafka image only
            # formats its storage with this one (verified locally - with
            # KAFKA_CLUSTER_ID it silently generates a random ID).
            name  = "CLUSTER_ID"
            value = random_id.tempo_kafka_cluster_id.b64_url
          }
          env {
            name  = "KAFKA_NODE_ID"
            value = "0"
          }
          env {
            name  = "KAFKA_PROCESS_ROLES"
            value = "broker,controller"
          }
          env {
            name  = "KAFKA_LISTENERS"
            value = "PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093"
          }
          env {
            name  = "KAFKA_ADVERTISED_LISTENERS"
            value = "PLAINTEXT://tempo-kafka-0.tempo-kafka-headless.observability.svc.cluster.local:9092"
          }
          env {
            name  = "KAFKA_CONTROLLER_QUORUM_VOTERS"
            value = "0@tempo-kafka-0.tempo-kafka-headless.observability.svc.cluster.local:9093"
          }
          env {
            name  = "KAFKA_CONTROLLER_LISTENER_NAMES"
            value = "CONTROLLER"
          }
          env {
            name  = "KAFKA_INTER_BROKER_LISTENER_NAME"
            value = "PLAINTEXT"
          }
          env {
            name  = "KAFKA_LOG_DIRS"
            value = "/var/lib/kafka/data"
          }
          env {
            name  = "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR"
            value = "1"
          }
          env {
            # Block-builders flush within minutes; a day covers a longer
            # Tempo outage without the volume growing much.
            name  = "KAFKA_LOG_RETENTION_HOURS"
            value = "24"
          }
          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              memory = "1Gi"
            }
          }
          readiness_probe {
            tcp_socket {
              port = "kafka"
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
          liveness_probe {
            tcp_socket {
              port = "kafka"
            }
            initial_delay_seconds = 60
            period_seconds        = 20
            failure_threshold     = 6
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/kafka"
          }
          volume_mount {
            name       = "config"
            mount_path = "/opt/kafka/config"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
          # Kafka 4.4 writes its log4j files here (read-only root fs).
          volume_mount {
            name       = "logs"
            mount_path = "/opt/kafka/logs"
          }
        }
        volume {
          name = "config"
          empty_dir {}
        }
        volume {
          name = "logs"
          empty_dir {}
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "5Gi"
          }
        }
      }
    }
  }
}

# Chart moves to grafana-community (loki 7.x -> 21.x, tempo-distributed
# 1.x -> 3.x) change the immutable serviceName of two StatefulSets, so
# helm upgrade would fail on them:
#   tempo-memcached  "memcached"  -> "tempo-memcached"  (only a cache)
#   loki-ruler       "loki-ruler" -> "loki-ruler-headless" (0 replicas here)
# The tempo-memcached Service also turns headless (clusterIP: None), and
# a Service's clusterIP is immutable too - found live, the upgrade failed
# with "spec.clusterIPs[0]: Invalid value: [None]: may not change once
# set". Delete them before the upgrade, which then creates them again.
# Each delete only runs while the old object is still live - a no-op on
# every later apply and on a fresh install.
resource "null_resource" "chart_statefulset_migrate" {
  triggers = {
    loki_chart  = "21.4.2"
    tempo_chart = "3.29.1"
    # Re-runs this step on clusters where it already ran before the
    # Service delete below existed.
    memcached_service = "headless"
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local_sensitive_file.kubeconfig.filename
    }
    command = <<-EOT
      set -e
      migrate() {
        if [ "$(kubectl -n observability get statefulset "$1" -o jsonpath='{.spec.serviceName}' --ignore-not-found)" = "$2" ]; then
          kubectl -n observability delete statefulset "$1" --wait=true
        fi
      }
      migrate tempo-memcached memcached
      migrate loki-ruler loki-ruler
      ip=$(kubectl -n observability get service tempo-memcached -o jsonpath='{.spec.clusterIP}' --ignore-not-found)
      if [ -n "$ip" ] && [ "$ip" != "None" ]; then
        kubectl -n observability delete service tempo-memcached --wait=true
      fi
    EOT
  }

  depends_on = [local_sensitive_file.kubeconfig]
}

# Tempo 2 -> 3: the upgrade removes tempo-ingester, and spans still in
# its WAL would be lost with it (Kafka only holds what Tempo 3's
# distributors write). /shutdown flushes everything to blob storage and
# leaves the ring first - the documented step before removing Tempo 2
# ingesters; this waits until the flush has finished. Traces arriving
# between this flush and the upgrade are lost (seconds). Only runs while a Tempo 2 ingester still exists.
resource "null_resource" "tempo_ingester_flush" {
  triggers = {
    tempo_chart = "3.29.1"
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local_sensitive_file.kubeconfig.filename
    }
    command = <<-EOT
      set -e
      if [ -n "$(kubectl -n observability get statefulset tempo-ingester -o name --ignore-not-found)" ]; then
        # Epoch arithmetic: the job image's busybox date has no relative
        # `-d '-1 min'` (GNU only), but both accept `-d @<seconds>`.
        since=$(date -u -d "@$(( $(date +%s) - 60 ))" +%Y-%m-%dT%H:%M:%SZ)
        kubectl -n observability exec tempo-ingester-0 -c ingester -- wget -qO- --post-data= http://localhost:3200/shutdown
        # The handler only acknowledges and flushes in the background
        # (modules/ingester/flush.go) - wait for its completion log line,
        # also in the previous container if the ingester exited after it.
        for _ in $(seq 120); do
          if { kubectl -n observability logs tempo-ingester-0 -c ingester --since-time="$since" 2>/dev/null
               kubectl -n observability logs tempo-ingester-0 -c ingester --previous --since-time="$since" 2>/dev/null; } \
             | grep -q 'shutdown handler complete'; then
            exit 0
          fi
          sleep 5
        done
        echo "tempo-ingester-0 did not finish flushing within 10 minutes" >&2
        exit 1
      fi
    EOT
  }

  depends_on = [local_sensitive_file.kubeconfig, kubernetes_stateful_set_v1.tempo_kafka, null_resource.chart_statefulset_migrate]
}

resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "tempo-distributed"
  version    = "3.30.1"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  values = [
    file("${path.module}/../../../helm/values/tempo-values.yaml"),
    # Per-tenant limits from scripts/provision.py - see the comment
    # above helm_release.loki.
    file("${path.module}/../../../helm/values/tempo-tenant-overrides.yaml"),
  ]

  set = [
    { name = "storage.trace.azure.storage_account_name", value = azurerm_storage_account.observability.name },
  ]
  set_sensitive = [
    { name = "storage.trace.azure.storage_account_key", value = azurerm_storage_account.observability.primary_access_key },
  ]

  # Tempo 3: block-builder, live-store and backend-scheduler/-worker
  # start fresh and replay Kafka - more than the 5-minute default.
  timeout = 900

  depends_on = [azurerm_storage_container.observability, kubernetes_stateful_set_v1.tempo_kafka, null_resource.tempo_ingester_flush]
}

# Mimir's chart ships hooks that create cluster-scoped webhook configs for
# zone-aware downscale protection - found live that these can end up
# orphaned (referencing stale pod IPs) after certain upgrade/reinstall
# cycles, causing the next mimir install/upgrade to fail. Idempotent,
# harmless if nothing is there - see scripts/install.sh's own comment for
# the original incident. Runs via local kubectl against a kubeconfig
# materialized from this module's own AKS data source (no
# `az aks get-credentials` needed) - the CI job installs just the kubectl
# binary for this one step, see .gitlab-ci.yml.
resource "local_sensitive_file" "kubeconfig" {
  content  = data.azurerm_kubernetes_cluster.main.kube_config_raw
  filename = "${path.module}/.terraform-kubeconfig"
}

resource "null_resource" "mimir_webhook_cleanup" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local_sensitive_file.kubeconfig.filename
    }
    command = <<-EOT
      kubectl delete mutatingwebhookconfiguration prepare-downscale-observability --ignore-not-found
      kubectl delete validatingwebhookconfiguration no-downscale-observability pod-eviction-observability zpdb-validation-observability --ignore-not-found
    EOT
  }

  depends_on = [local_sensitive_file.kubeconfig]
}

resource "helm_release" "mimir" {
  name       = "mimir"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "mimir-distributed"
  version    = "6.2.2"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  values = [
    file("${path.module}/../../../helm/values/mimir-values.yaml"),
    # Per-tenant limits from scripts/provision.py - see the comment
    # above helm_release.loki.
    file("${path.module}/../../../helm/values/mimir-tenant-overrides.yaml"),
  ]

  # Mimir's Azure Blob client doesn't support Workload Identity (see this
  # file's own Azure Blob Storage header comment) - account_key goes
  # straight into the Helm release via set_sensitive, never into the
  # checked-in values.yaml file.
  set = [
    { name = "mimir.structuredConfig.blocks_storage.azure.account_name", value = azurerm_storage_account.observability.name },
    { name = "mimir.structuredConfig.common.storage.azure.account_name", value = azurerm_storage_account.observability.name },
  ]
  set_sensitive = [
    { name = "mimir.structuredConfig.blocks_storage.azure.account_key", value = azurerm_storage_account.observability.primary_access_key },
    { name = "mimir.structuredConfig.common.storage.azure.account_key", value = azurerm_storage_account.observability.primary_access_key },
  ]

  depends_on = [azurerm_storage_container.observability, null_resource.mimir_webhook_cleanup]
}

resource "helm_release" "pyroscope" {
  name       = "pyroscope"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "pyroscope"
  version    = "2.4.4"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  values = [
    file("${path.module}/../../../helm/values/pyroscope-values.yaml"),
    # Per-tenant limits from scripts/provision.py - see the comment
    # above helm_release.loki.
    file("${path.module}/../../../helm/values/pyroscope-tenant-overrides.yaml"),
  ]

  # Same reasoning as Mimir above - Pyroscope's own config reference
  # doesn't document a federated-token field for its azure storage
  # backend, so this uses the account key too. The chart renders its
  # config into a ConfigMap with no Secret option, so the key itself
  # lives in kubernetes_secret_v1.pyroscope_storage below and the config
  # only gets a placeholder, expanded at startup (-config.expand-env,
  # see pyroscope-values.yaml). "$${...}" is Terraform's escape for a
  # literal "${...}".
  set = [
    { name = "pyroscope.structuredConfig.storage.azure.account_name", value = azurerm_storage_account.observability.name },
    { name = "pyroscope.structuredConfig.storage.azure.account_key", value = "$${AZURE_STORAGE_ACCOUNT_KEY}" },
  ]
  # The rendered config no longer changes when the key does, and pods
  # only read a Secret env var at start - this checksum changes the pod
  # template on every key rotation, so all Pyroscope pods restart with
  # the new key instead of keeping the revoked one.
  set_sensitive = [
    { name = "pyroscope.podAnnotations.checksum/storage-key", value = sha256(azurerm_storage_account.observability.primary_access_key) },
  ]

  depends_on = [azurerm_storage_container.observability, kubernetes_secret_v1.pyroscope_storage]
}

# F24/NFR-03: the storage account key for Pyroscope, injected as an
# environment variable (pyroscope-values.yaml extraEnvFrom) instead of
# being rendered into the pyroscope-config ConfigMap.
resource "kubernetes_secret_v1" "pyroscope_storage" {
  metadata {
    name      = "pyroscope-storage"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  data = {
    AZURE_STORAGE_ACCOUNT_KEY = azurerm_storage_account.observability.primary_access_key
  }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "grafana"
  version    = "14.6.1"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  values     = [file("${path.module}/../../../helm/values/grafana-values.yaml")]

  # Empty (the default) means "don't override" - the chart falls back to
  # its own behavior of auto-generating a random password into the
  # "grafana" Secret's admin-password key, same as before this variable
  # existed (see README's "Get the admin password" kubectl snippet).
  # Only set when non-empty: an unconditional set_sensitive with an empty
  # string would actively set the admin password to "", not skip it.
  # checksum/openclaw-hooks-token: Grafana reads the mounted token file
  # only when it (re)provisions alerting, so a rotated token must restart
  # the pod. A SHA-256 of a long random token reveals nothing usable.
  set_sensitive = concat(
    var.grafana_admin_password != "" ? [
      { name = "adminPassword", value = var.grafana_admin_password },
    ] : [],
    [
      { name = "podAnnotations.checksum/openclaw-hooks-token", value = sha256(var.openclaw_hooks_token) },
    ],
  )

  depends_on = [helm_release.loki, helm_release.tempo, helm_release.mimir, helm_release.pyroscope, kubernetes_manifest.secret_provider_class]
}

# F05/NFR-03: OpenClaw's hook token for Grafana's webhook contact point,
# mounted into Grafana as a file (grafana-values.yaml extraSecretMounts).
# Lives in this state, not in ../tenants with the contact point itself,
# so the mount and its Secret are always created together - Grafana
# would fail to provision alerting if the file were missing.
# G12: the token now lives in the Key Vault (azurerm_key_vault_secret.
# openclaw_hooks_token) and is mounted via the CSI driver - the former
# Kubernetes Secret grafana-openclaw-hooks is no longer in this state,
# so Terraform deletes it on the next apply.

# ---------------------------------------------------------------------------
# Grafana dashboards - genuinely tenant-agnostic ones only (shared/,
# e.g. the operator budget dashboard and the collector self-monitoring
# one). 4087's own dashboard used to also live here, existing before
# any onboarding happened - moved to ../tenants, applied by
# deploy:tenants like every other tenant's own dashboard (IaC Roadmap
# milestone, done - see main README's Multi-Tenancy section).
# ---------------------------------------------------------------------------

locals {
  repo_root         = "${path.module}/../../.."
  shared_dashboards = fileset("${local.repo_root}/dashboards/shared", "*.json")
  dashboards = {
    for f in local.shared_dashboards : "shared-${trimsuffix(f, ".json")}" => {
      folder   = "shared"
      filename = f
      path     = "${local.repo_root}/dashboards/shared/${f}"
    }
  }
}

resource "kubernetes_config_map_v1" "dashboards" {
  for_each = local.dashboards

  metadata {
    name      = "grafana-dashboard-${each.key}"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
    annotations = {
      grafana_folder = each.value.folder
    }
  }

  data = {
    (each.value.filename) = file(each.value.path)
  }
}

# ---------------------------------------------------------------------------
# OTel Operator (self-signed webhook certs, no cert-manager dependency -
# the CRDs it installs are what ../observability-stack-crs's
# kubernetes_manifest resources need present before they can be planned)
# ---------------------------------------------------------------------------

resource "helm_release" "opentelemetry_operator" {
  name       = "opentelemetry-operator"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-operator"
  version    = "0.129.2"
  namespace  = kubernetes_namespace_v1.otel_operator.metadata[0].name

  set = [
    { name = "manager.collectorImage.repository", value = "otel/opentelemetry-collector-contrib" },
    # Default image for CRs without spec.image; the chart would otherwise
    # use its own appVersion-matched tag (older than our pinned collector).
    { name = "manager.collectorImage.tag", value = "0.166.0" },
    { name = "admissionWebhooks.certManager.enabled", value = "false" },
    { name = "admissionWebhooks.autoGenerateCert.enabled", value = "true" },
  ]
}

# RBAC for the OTel Collector CRs' ServiceAccounts (k8sattributes processor,
# kubeletstats receiver) - plain core RBAC types, no CRD involved, so this
# stays here rather than in ../observability-stack-crs even though the
# collectors it serves are CRD instances applied there.

resource "kubernetes_cluster_role_v1" "otel_collector_k8sattributes" {
  metadata {
    name = "otel-collector-k8sattributes"
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["replicasets", "daemonsets", "deployments", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "otel_collector_k8sattributes" {
  metadata {
    name = "otel-collector-k8sattributes"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.otel_collector_k8sattributes.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "otel-gateway-collector"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
}

# Needed by the agent DaemonSet's kubeletstats receiver, which calls the
# kubelet's /stats/summary endpoint directly (not via the API server
# proxy) - a pure in-cluster RBAC check, unrelated to Azure RBAC.
resource "kubernetes_cluster_role_v1" "otel_collector_kubeletstats" {
  metadata {
    name = "otel-collector-kubeletstats"
  }
  rule {
    api_groups = [""]
    resources  = ["nodes/stats"]
    verbs      = ["get"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "otel_collector_kubeletstats" {
  metadata {
    name = "otel-collector-kubeletstats"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.otel_collector_kubeletstats.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "otel-agent-collector"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
}

# ---------------------------------------------------------------------------
# Internal LoadBalancers for the VMs - the internal annotation must be
# present at creation time (annotating after creation provisions a public
# IP instead, found the hard way - see scripts/setup-gateway-internal.sh's
# original comment).
#
# The plain-OTLP LoadBalancer otel-gateway-internal is gone (F03): it
# accepted a client-chosen tenant_id from anywhere in the VNet. VMs now
# send only via traefik_otlp_internal (mTLS, tenant bound to the client
# certificate) and profiles via pyroscope_internal (tenant bound to the
# Basic-Auth credentials, see pyroscope_ingest_proxy).
# ---------------------------------------------------------------------------

# NFR-04 mTLS rollout, Phase 3 (README "Open Points") - an internal
# LoadBalancer fronting Traefik's own new "otlpmtls" entrypoint (helm/values/
# traefik-values.yaml) instead of the Gateway directly. Deliberately
# NOT the same Service Traefik's own Helm chart manages (that one is
# public, for web/websecure) - this stays platform-scoped and static
# (one fixed port, forever) precisely so the per-tenant routing that
# actually varies with onboarding (IngressRouteTCP/TLSOption,
# terraform/environments/tenants/main.tf) never has to touch this
# state or this Service at all.
resource "kubernetes_service_v1" "traefik_otlp_internal" {
  metadata {
    name = "traefik-otlp-internal"
    # Referenced, not a literal "ingress-traefik": that namespace only
    # exists once helm_release.traefik (create_namespace) has run. With
    # a literal there is no dependency between the two, and on a fresh
    # cluster Terraform creates this Service first and fails with
    # 'namespaces "ingress-traefik" not found'.
    namespace = helm_release.traefik.namespace
    annotations = {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
    }
  }
  spec {
    type = "LoadBalancer"
    selector = {
      "app.kubernetes.io/name"     = "traefik"
      "app.kubernetes.io/instance" = "traefik-ingress-traefik"
    }
    port {
      name        = "otlpmtls"
      port        = 14317
      target_port = 14317
    }
  }
}

# ---------------------------------------------------------------------------
# Pyroscope ingest proxy (F03). Pyroscope OSS has no authentication and
# takes the tenant from the client's X-Scope-OrgID header. Every profile
# push - from the VMs (pyroscope_internal) and from pods (Service
# pyroscope-ingest) - goes through this nginx instead: Basic Auth with
# user = tenant_id, password per tenant (generated in
# terraform/environments/tenants, Secret pyroscope-ingest-htpasswd), and
# X-Scope-OrgID is then set from the authenticated user, overwriting any
# client value. Only the push endpoints are forwarded; Pyroscope's query
# APIs stay unreachable through it. The backends themselves are only
# reachable from inside this namespace (kubernetes_network_policy_v1.
# observability_backends).
#
# {PLAIN} passwords in the htpasswd file: nginx re-reads the file on
# every request (new tenants need no restart) and the file lives in a
# Secret, same as the credentials themselves. The VM -> proxy hop stays
# plain HTTP inside the VNet (documented residual risk, README).
# ---------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "pyroscope_ingest_proxy" {
  metadata {
    name      = "pyroscope-ingest-proxy"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  data = {
    "nginx.conf" = <<-EOT
      worker_processes 1;
      pid /tmp/nginx.pid;
      error_log /dev/stderr warn;
      events { worker_connections 256; }
      http {
        client_body_temp_path /tmp/client_temp;
        proxy_temp_path /tmp/proxy_temp;
        fastcgi_temp_path /tmp/fastcgi_temp;
        uwsgi_temp_path /tmp/uwsgi_temp;
        scgi_temp_path /tmp/scgi_temp;
        access_log /dev/stdout;
        client_max_body_size 32m;
        server_tokens off;
        server {
          listen 8080;
          location = /healthz { access_log off; return 200 "ok\n"; }
          location ~ ^/(ingest|push\.v1\.PusherService/Push)$ {
            auth_basic "pyroscope-ingest";
            auth_basic_user_file /etc/pyroscope-ingest/htpasswd;
            proxy_set_header X-Scope-OrgID $remote_user;
            proxy_set_header Authorization "";
            proxy_pass http://pyroscope-distributor.observability.svc.cluster.local:4040;
          }
          location / { return 404; }
        }
      }
    EOT
  }
}

resource "kubernetes_deployment_v1" "pyroscope_ingest_proxy" {
  metadata {
    name      = "pyroscope-ingest-proxy"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "pyroscope-ingest-proxy"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "pyroscope-ingest-proxy"
      }
    }
    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "pyroscope-ingest-proxy"
        }
        annotations = {
          "checksum/config" = sha256(kubernetes_config_map_v1.pyroscope_ingest_proxy.data["nginx.conf"])
        }
      }
      spec {
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name  = "nginx"
          image = "nginx/nginx-unprivileged:1.31.10-alpine"
          port {
            name           = "http"
            container_port = 8080
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "64Mi"
            }
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds = 10
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
            read_only  = true
          }
          volume_mount {
            name       = "htpasswd"
            mount_path = "/etc/pyroscope-ingest"
            read_only  = true
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.pyroscope_ingest_proxy.metadata[0].name
          }
        }
        volume {
          name = "htpasswd"
          secret {
            # Created by terraform/environments/tenants (applied after
            # this state). optional: the proxy starts without it and
            # answers 500 until the first tenant rollout; the mounted
            # file updates in place afterwards (no subPath).
            secret_name = "pyroscope-ingest-htpasswd"
            optional    = true
          }
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
}

# In-cluster endpoint for pods (e.g. fleet-4139's Java app).
resource "kubernetes_service_v1" "pyroscope_ingest" {
  metadata {
    name      = "pyroscope-ingest"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "pyroscope-ingest-proxy"
    }
    port {
      name        = "http"
      port        = 4040
      target_port = "http"
    }
  }
}

# Internal LoadBalancer for the VM-based apps (4711 Tomcat, 4722
# Spesenabrechnung), see B12 in the main README. Same name and IP as
# before; it now points at the ingest proxy instead of Pyroscope's
# distributor.
resource "kubernetes_service_v1" "pyroscope_internal" {
  metadata {
    name      = "pyroscope-internal"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
    }
  }
  spec {
    type = "LoadBalancer"
    selector = {
      "app.kubernetes.io/name" = "pyroscope-ingest-proxy"
    }
    port {
      port        = 4040
      target_port = "http"
    }
  }
}

# ---------------------------------------------------------------------------
# F02: Mimir, Loki, Tempo and Pyroscope take the tenant from the
# X-Scope-OrgID header without any authentication, so whoever reaches
# them can read and write every tenant. Only pods in this namespace (the
# platform's own components: Grafana, OTel gateway/agent, budget
# enforcer, ingest proxy, the backends themselves) and linkerd's control
# plane/viz (proxy admin and metrics ports) may connect. Tenant workloads
# write through the OTel gateway and the Pyroscope ingest proxy, both
# unrestricted here and both binding the tenant server-side.
# kubectl port-forward is unaffected (it doesn't use the pod network).
# Verified live before rollout with Calico (AKS network policy engine):
# cross-namespace traffic blocked, linkerd-meshed same-namespace traffic
# and kubelet probes unaffected.
# ---------------------------------------------------------------------------
resource "kubernetes_network_policy_v1" "observability_backends" {
  metadata {
    name      = "observability-backends-ingress"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  spec {
    pod_selector {
      match_expressions {
        key      = "app.kubernetes.io/name"
        operator = "In"
        values   = ["mimir", "loki", "tempo", "tempo-kafka", "pyroscope"]
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = kubernetes_namespace_v1.observability.metadata[0].name
          }
        }
      }
      from {
        namespace_selector {
          match_expressions {
            key      = "kubernetes.io/metadata.name"
            operator = "In"
            values   = ["linkerd", "linkerd-viz"]
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Ingress: Traefik + cert-manager
# ---------------------------------------------------------------------------

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "43.0.0"
  namespace        = "ingress-traefik"
  create_namespace = true
  values           = [file("${path.module}/../../../helm/values/traefik-values.yaml")]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.21.3"
  namespace        = "cert-manager"
  create_namespace = true

  set = [
    { name = "crds.enabled", value = "true" },
  ]
}

resource "kubernetes_secret_v1" "azuredns_config" {
  count = var.cert_manager_client_id != "" ? 1 : 0

  metadata {
    name      = "azuredns-config"
    namespace = "cert-manager"
  }
  data = {
    CLIENT_SECRET = var.cert_manager_client_secret
  }

  depends_on = [helm_release.cert_manager]
}

# Wait for Traefik's LoadBalancer to get an IP before reading it below -
# a fixed wait rather than the old script's 5-minute retry loop (30x10s):
# if 60s isn't enough, this apply fails and a re-run picks it up, same as
# any other transient CI failure - see the plan's own note on this
# simplification.
resource "time_sleep" "wait_for_traefik_ip" {
  depends_on      = [helm_release.traefik]
  create_duration = "60s"
}

data "kubernetes_service_v1" "traefik" {
  metadata {
    name      = "traefik"
    namespace = "ingress-traefik"
  }
  depends_on = [time_sleep.wait_for_traefik_ip]
}

# Replaces the old delete-then-add `az network dns record-set` shell
# dance (worked around stale IPs accumulating across rebuilds, since
# add-record alone only appends) - a normal Terraform resource already
# updates in place instead of accumulating.
resource "azurerm_dns_a_record" "grafana" {
  name                = "grafana"
  zone_name           = data.azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip]
}

# Gives the shared "Ingestion Budget Usage" alert/dashboard
# (alerting/shared/operator-ingestion-budget.yaml,
# dashboards/shared/operator-tenant-budget.json) a real calendar-day
# reset - Grafana alert rules have no "since midnight" time range (only
# a fixed rolling duration back from now), so a genuine daily reset
# needs an actual value snapshotted at midnight to subtract from later.
# Mimir's own ruler could otherwise run a one-line recording rule for
# this, but it's deliberately scaled to 0 in this repo (see
# helm/values/mimir-values.yaml, "not needed for demo") - not
# reactivated just for this one snapshot.
#
# Also the active enforcement point for each tenant's daily budget (see
# the script's own header for the full design) - runs every 2 minutes
# rather than once at midnight, both to beat Prometheus's 5-minute
# staleness window on the gauges it pushes (found live) and to react to
# a tenant crossing 100% of its budget reasonably quickly.
resource "kubernetes_config_map_v1" "ingestion_midnight_snapshot_script" {
  metadata {
    name      = "ingestion-midnight-snapshot-script"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  data = {
    "snapshot.py" = file("${path.module}/../../../scripts/ingestion-midnight-snapshot.py")
  }
}

# Persisted state (current day, midnight-snapshot values, currently-
# throttled tenants) the enforcer script reads/writes across runs via
# the Kubernetes API - starts empty, populated on first run. Managed as
# an empty shell here (lifecycle.ignore_changes on data) so Terraform
# never fights the script's own writes to it.
resource "kubernetes_config_map_v1" "ingestion_snapshot_state" {
  metadata {
    name      = "ingestion-midnight-snapshot-state"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  data = {}
  lifecycle {
    ignore_changes = [data]
  }
}

# Scoped to exactly the 5 ConfigMaps the enforcer script needs to read/
# write - no broader configmap access, no create (the state ConfigMap
# above is pre-created by Terraform so the script never needs to create
# one itself).
resource "kubernetes_service_account_v1" "ingestion_budget_enforcer" {
  metadata {
    name      = "ingestion-budget-enforcer"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
}

resource "kubernetes_role_v1" "ingestion_budget_enforcer" {
  metadata {
    name      = "ingestion-budget-enforcer"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["mimir-runtime", "loki-runtime", "tempo-runtime", "pyroscope-overrides-config", "ingestion-midnight-snapshot-state"]
    verbs          = ["get", "patch", "update"]
  }
}

resource "kubernetes_role_binding_v1" "ingestion_budget_enforcer" {
  metadata {
    name      = "ingestion-budget-enforcer"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.ingestion_budget_enforcer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ingestion_budget_enforcer.metadata[0].name
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
}

# ---------------------------------------------------------------------------
# G06 (FR-09): storage-usage CronJob - measured object-storage volume per
# tenant and signal (scripts/storage-usage.py), for the showback
# dashboard (dashboards/shared/operator-storage-showback.json). Lists the
# containers with a read/list-only account SAS, not the account key; the
# SAS is re-issued every 90 days (time_rotating) and valid for 180, so a
# skipped deploy never leaves the job with an expired token. The SAS is
# stored in the Key Vault and mounted via the CSI driver (G12).
# ---------------------------------------------------------------------------

resource "time_rotating" "storage_usage_sas" {
  rotation_days = 90
}

data "azurerm_storage_account_sas" "storage_usage" {
  connection_string = azurerm_storage_account.observability.primary_connection_string
  https_only        = true
  signed_version    = "2022-11-02"
  start             = time_rotating.storage_usage_sas.rfc3339
  expiry            = timeadd(time_rotating.storage_usage_sas.rfc3339, "4320h")

  resource_types {
    service   = false
    container = true
    object    = false
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  permissions {
    read    = true
    list    = true
    write   = false
    delete  = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

# ---------------------------------------------------------------------------
# G12 (NFR-03): platform Key Vault + Secrets Store CSI driver (AKS add-on,
# terraform/modules/aks-cluster). Pods mount secrets from here as files
# via a SecretProviderClass - the value never exists as a Kubernetes
# Secret in etcd. Consumers so far: Grafana's OpenClaw hook token and the
# storage-usage CronJob's SAS. Remaining Kubernetes Secrets and why: see
# README "Secrets".
#
# Access policies, not Azure RBAC: the CI Service Principal is only
# Contributor on the resource group and may not create role assignments
# (README Known Pitfalls) - access policies are part of the vault itself.
# Values are written write-only (value_wo): the hook token (a variable)
# is not stored in the Terraform state. The SAS is anyway - it comes from
# a data source (read/list-only, rotated every 90 days).
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

locals {
  # Identity of the AKS Key Vault add-on - requires deploy:infra with
  # key_vault_secrets_provider enabled before this state is applied.
  kv_addon_identity = data.azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0]
}

# Accepted demo trade-off, same as the storage account above: no network
# ACL (default Deny) - the CI runner and the AKS nodes reach the vault
# over public egress IPs that aren't stable inputs of this state, and a
# Key Vault service endpoint would have to go on the manually
# bootstrapped aks-vnet. Access is limited by the access policies below.
#trivy:ignore:AZU-0013
resource "azurerm_key_vault" "platform" {
  name                       = "kv-otel-${random_id.storage_account_suffix.hex}"
  location                   = data.azurerm_kubernetes_cluster.main.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = false
  soft_delete_retention_days = 7
  # Demo: no purge protection, so destroy:infra can purge and a rebuild
  # can reuse the name (provider feature purge_soft_delete_on_destroy).
  purge_protection_enabled = false
}

resource "azurerm_key_vault_access_policy" "ci" {
  key_vault_id       = azurerm_key_vault.platform.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = data.azurerm_client_config.current.object_id
  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

resource "azurerm_key_vault_access_policy" "aks_csi" {
  key_vault_id       = azurerm_key_vault.platform.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = local.kv_addon_identity.object_id
  secret_permissions = ["Get"]
}

resource "azurerm_key_vault_secret" "openclaw_hooks_token" {
  name         = "grafana-openclaw-hooks-token"
  key_vault_id = azurerm_key_vault.platform.id
  value_wo     = var.openclaw_hooks_token
  # Write-only values are only re-sent when the version changes - derived
  # from the value's hash (8 hex chars of a SHA-256 reveal nothing usable).
  value_wo_version = parseint(substr(sha256(var.openclaw_hooks_token), 0, 8), 16)
  depends_on       = [azurerm_key_vault_access_policy.ci]

  lifecycle {
    precondition {
      condition     = var.openclaw_hooks_token != ""
      error_message = "OPENCLAW_HOOKS_TOKEN must be set: Grafana mounts this secret and does not start without it."
    }
  }
}

resource "azurerm_key_vault_secret" "storage_usage_sas" {
  name             = "storage-usage-sas"
  key_vault_id     = azurerm_key_vault.platform.id
  value_wo         = data.azurerm_storage_account_sas.storage_usage.sas
  value_wo_version = time_rotating.storage_usage_sas.unix
  depends_on       = [azurerm_key_vault_access_policy.ci]
}

# One SecretProviderClass per consumer, so each pod can read only its own
# secret. The CRD comes with the AKS add-on (deploy:infra).
resource "kubernetes_manifest" "secret_provider_class" {
  for_each = {
    "grafana-openclaw-hooks" = { object = azurerm_key_vault_secret.openclaw_hooks_token.name, alias = "token" }
    "storage-usage"          = { object = azurerm_key_vault_secret.storage_usage_sas.name, alias = "STORAGE_SAS" }
  }

  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = each.key
      namespace = kubernetes_namespace_v1.observability.metadata[0].name
    }
    spec = {
      provider = "azure"
      parameters = {
        usePodIdentity         = "false"
        useVMManagedIdentity   = "true"
        userAssignedIdentityID = local.kv_addon_identity.client_id
        keyvaultName           = azurerm_key_vault.platform.name
        tenantId               = data.azurerm_client_config.current.tenant_id
        objects                = yamlencode({ array = [yamlencode({ objectName = each.value.object, objectType = "secret", objectAlias = each.value.alias })] })
      }
    }
  }

  depends_on = [azurerm_key_vault_access_policy.aks_csi]
}

resource "kubernetes_config_map_v1" "storage_usage_script" {
  metadata {
    name      = "storage-usage-script"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  data = {
    "storage-usage.py" = file("${path.module}/../../../scripts/storage-usage.py")
    # Remote-write encoder and budget reader, imported by storage-usage.py.
    "snapshot.py" = file("${path.module}/../../../scripts/ingestion-midnight-snapshot.py")
  }
}

resource "kubernetes_cron_job_v1" "storage_usage" {
  metadata {
    name      = "storage-usage"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  spec {
    schedule                      = "17 * * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3
    job_template {
      metadata {}
      spec {
        backoff_limit = 2
        template {
          metadata {
            # Unmeshed for the same reason as ingestion-midnight-snapshot
            # above: a meshed Job pod never completes.
            annotations = {
              "linkerd.io/inject" = "disabled"
            }
          }
          spec {
            restart_policy                  = "OnFailure"
            automount_service_account_token = false
            container {
              name    = "storage-usage"
              image   = "python:3.15.2-slim"
              command = ["python3", "/scripts/storage-usage.py"]
              env {
                name  = "STORAGE_ACCOUNT"
                value = azurerm_storage_account.observability.name
              }
              env {
                name  = "STORAGE_SAS_FILE"
                value = "/mnt/secrets/STORAGE_SAS"
              }
              volume_mount {
                name       = "script"
                mount_path = "/scripts"
              }
              volume_mount {
                name       = "secrets"
                mount_path = "/mnt/secrets"
                read_only  = true
              }
              volume_mount {
                name       = "budgets"
                mount_path = "/budgets"
              }
            }
            volume {
              name = "script"
              config_map {
                name = kubernetes_config_map_v1.storage_usage_script.metadata[0].name
              }
            }
            # G12: the SAS comes from the Key Vault via the CSI driver.
            volume {
              name = "secrets"
              csi {
                driver    = "secrets-store.csi.k8s.io"
                read_only = true
                volume_attributes = {
                  secretProviderClass = kubernetes_manifest.secret_provider_class["storage-usage"].manifest.metadata.name
                }
              }
            }
            volume {
              name = "budgets"
              config_map {
                name     = "tenant-ingestion-budgets"
                optional = true
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_cron_job_v1" "ingestion_midnight_snapshot" {
  metadata {
    name      = "ingestion-midnight-snapshot"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  spec {
    # Matches this dashboard's own `timezone: "browser"` setting for a
    # viewer in this timezone - AKS nodes confirmed on Kubernetes 1.35,
    # so spec.timeZone (stable since 1.27) is safely supported.
    schedule                      = "*/2 * * * *"
    timezone                      = "Europe/Zurich"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3
    job_template {
      metadata {}
      spec {
        template {
          metadata {
            # Opt out of the observability namespace's Linkerd injection
            # (NFR-04 Phase 4, see kubernetes_namespace_v1.observability).
            # A meshed Job pod never completes: the linkerd-proxy sidecar
            # keeps running after this container exits, the Job stays
            # active, and concurrency_policy Forbid then skips every later
            # run - budget enforcement silently stops after the first
            # meshed run (seen live on a fresh cluster). Linkerd 2.14 has
            # neither native sidecars nor the proxy shutdown endpoint, so
            # there is no way to keep this pod meshed and still let it
            # finish. Connectivity is unaffected: no inbound policy is
            # configured, so Mimir still accepts this unmeshed client;
            # only this hop is plain HTTP instead of mTLS.
            annotations = {
              "linkerd.io/inject" = "disabled"
            }
          }
          spec {
            restart_policy       = "OnFailure"
            service_account_name = kubernetes_service_account_v1.ingestion_budget_enforcer.metadata[0].name
            container {
              name    = "snapshot"
              image   = "python:3.15.2-slim"
              command = ["python3", "/scripts/snapshot.py"]
              volume_mount {
                name       = "script"
                mount_path = "/scripts"
              }
              volume_mount {
                name       = "budgets"
                mount_path = "/budgets"
              }
            }
            volume {
              name = "script"
              config_map {
                name = kubernetes_config_map_v1.ingestion_midnight_snapshot_script.metadata[0].name
              }
            }
            # Per-tenant daily budgets, generated by scripts/provision.py
            # on every onboarding run - owned by terraform/environments/
            # tenants (ConfigMap "tenant-ingestion-budgets"), not this
            # state: found live that this state used to own it, so an
            # onboarding pipeline's deploy:observability-stack rolled
            # out the budgets file from the merge commit, i.e. BEFORE
            # tenants:apply had committed the regenerated one - new
            # tenants got no budget until the next stack deploy. The
            # tenants state applies in tenants:rollout, from
            # tenants:apply's own artifact. Referenced by name (cross-
            # state) and optional: on a fresh build this CronJob exists
            # before the first tenants:rollout, and a missing required
            # ConfigMap would leave its pods stuck in ContainerCreating -
            # with concurrency_policy Forbid that blocks every later run
            # too. The script exits cleanly while the file is absent.
            volume {
              name = "budgets"
              config_map {
                name     = "tenant-ingestion-budgets"
                optional = true
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.mimir, kubernetes_config_map_v1.ingestion_snapshot_state]
}

# moved blocks for the kubernetes provider v3 rename -
# unversioned resource types deprecated in favour of _v1 (see
# the provider's own v3.0.0 CHANGELOG) - required so Terraform
# treats this as a rename of the same live object, not a
# destroy+recreate.
moved {
  from = kubernetes_namespace.observability
  to   = kubernetes_namespace_v1.observability
}

moved {
  from = kubernetes_namespace.otel_operator
  to   = kubernetes_namespace_v1.otel_operator
}

moved {
  from = kubernetes_config_map.dashboards
  to   = kubernetes_config_map_v1.dashboards
}

moved {
  from = kubernetes_cluster_role.otel_collector_k8sattributes
  to   = kubernetes_cluster_role_v1.otel_collector_k8sattributes
}

moved {
  from = kubernetes_cluster_role_binding.otel_collector_k8sattributes
  to   = kubernetes_cluster_role_binding_v1.otel_collector_k8sattributes
}

moved {
  from = kubernetes_cluster_role.otel_collector_kubeletstats
  to   = kubernetes_cluster_role_v1.otel_collector_kubeletstats
}

moved {
  from = kubernetes_cluster_role_binding.otel_collector_kubeletstats
  to   = kubernetes_cluster_role_binding_v1.otel_collector_kubeletstats
}

moved {
  from = kubernetes_service.pyroscope_internal
  to   = kubernetes_service_v1.pyroscope_internal
}

moved {
  from = kubernetes_secret.azuredns_config
  to   = kubernetes_secret_v1.azuredns_config
}

moved {
  from = kubernetes_config_map.ingestion_midnight_snapshot_script
  to   = kubernetes_config_map_v1.ingestion_midnight_snapshot_script
}

moved {
  from = kubernetes_config_map.ingestion_snapshot_state
  to   = kubernetes_config_map_v1.ingestion_snapshot_state
}

moved {
  from = kubernetes_service_account.ingestion_budget_enforcer
  to   = kubernetes_service_account_v1.ingestion_budget_enforcer
}

moved {
  from = kubernetes_role.ingestion_budget_enforcer
  to   = kubernetes_role_v1.ingestion_budget_enforcer
}

moved {
  from = kubernetes_role_binding.ingestion_budget_enforcer
  to   = kubernetes_role_binding_v1.ingestion_budget_enforcer
}
