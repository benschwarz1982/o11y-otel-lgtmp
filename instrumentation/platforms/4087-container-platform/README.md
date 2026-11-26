# Kubernetes / AKS - Instrumentation Guide

[← Back to the template index](../../README.md) - layer 2 of the
[3-layer model](../../schema/README.md) (schema → **platform/
runtime** → application). Template: [`config.yaml`](config.yaml) -
unlike the VM platforms, this one isn't rendered by Ansible at deploy
time: Terraform reads it directly
(`yamldecode(file(...))` in `terraform/environments/observability-
stack-crs/main.tf`) and applies it as an `OpenTelemetryCollector` CR
via the OTel Operator - no placeholder substitution needed, every
value in it is already final. See [README.md's
B2](../../../docs/setup.md#b2-lgtmp-stack--otel-collectors) for how it's
deployed.

## 1. Architecture

```
AKS Node                                  AKS Node
┌─────────────────────┐                  ┌─────────────────────┐
│ OTel Agent DaemonSet │                  │ OTel Agent DaemonSet │
│ hostmetrics/kubeletstats/filelog        │ (same, one per node) │
└──────────┬───────────┘                  └──────────┬───────────┘
           │ routing/logs connector                    │
           │ (per-namespace tenant routing)             │
           └───────────────────┬───────────────────────┘
                                ▼ OTLP/gRPC
                     OTel Gateway (Deployment, 2 replicas)
                     headers_setter, filter/reject_unknown_tenants
                                │
                     Mimir / Loki / Tempo (multi-tenant)
```

One agent per node (DaemonSet), not per pod - it serves the whole
node's host/kubelet metrics and every pod's container logs, routed to
each log's *owning* application tenant via a `routing` connector (not
the agent's own platform tenant) - see [Multi-
Tenancy](../../../docs/setup.md#b9-multi-tenancy-onboarding) and [Known
Pitfalls](../../../docs/known-pitfalls.md#known-pitfalls) for why that routing
exists (container logs used to land under the platform tenant for
every app, found live).

## 2. Installation

Applied via the OTel Operator (`observability-stack`'s
`opentelemetry_operator` `helm_release`) reading this `Open
TelemetryCollector` CR - no manual per-node install, see
[B2](../../../docs/setup.md#b2-lgtmp-stack--otel-collectors).

## 3. Collector Config Walkthrough

- **`hostmetrics`**: CPU/memory/disk/filesystem/network/load - no
  `processes` scraper, same cardinality reasoning as the [Linux
  template](../1286-linux-basis/#5-known-pitfalls).
- **`kubeletstats`**: container/pod/node/volume-level Kubernetes
  metrics, via the kubelet's own `/stats/summary` endpoint - needs a
  dedicated `ClusterRole`/`ClusterRoleBinding` (`nodes/stats: get`,
  `terraform/environments/observability-stack/main.tf`'s
  `kubernetes_cluster_role.otel_collector_kubeletstats`), see Known
  Pitfalls.
- **`filelog`**: container logs, pointed at the real kubelet log path
  (`/var/log/pods/*/*/*.log`, not the `/var/log/containers/*.log`
  symlinks - see Known Pitfalls for why that distinction matters),
  `format: containerd` (AKS's actual runtime, not `crio`).
- **`routing/logs`** connector: routes each known namespace's logs to
  its own tenant exporter - the mechanism that makes container-log
  multi-tenancy actually correct (see Multi-Tenancy above).
- **`resource`**: `platform.type: kubernetes`, `platform.vendor:
  azure-aks` - this schema's Core Schema attributes, static.

## 4. Validation

```bash
kubectl get pods -n observability -l app.kubernetes.io/name=otel-agent
kubectl logs -n observability -l app.kubernetes.io/name=otel-agent --tail=50
```

## 5. Known Pitfalls

See [README.md's Known
Pitfalls](../../../docs/known-pitfalls.md#known-pitfalls) for the full write-up of
each - this platform accumulated more of these than any other, since
it's the one every onboarded Kubernetes-based application's telemetry
actually flows through:
- `kubeletstats` `403 Forbidden` from missing RBAC.
- Container log parser set to the wrong format (`crio` vs. AKS's real
  `containerd`).
- `filelog` pointed at the wrong path, silently mislabeling every log
  as coming from the agent itself.
- Container logs landing under the platform tenant instead of their
  owning application's tenant (the `routing/logs` connector's origin
  story).
- No self-monitoring metrics until a dedicated `prometheus/self`
  pipeline was added, kept out of the shared `resource` processor
  (which would otherwise overwrite `service.name`/`service.namespace`).

## Rollout Checklist

| Step | Description | Status |
|---|---|---|
| 1 | OTel Operator installed (cert-manager prerequisite) | ☐ |
| 2 | Agent DaemonSet CR applied, RBAC for `kubeletstats`/`k8sattributes` confirmed | ☐ |
| 3 | `routing/logs` table covers every namespace that needs its own tenant | ☐ |
| 4 | Validate: agent pods `Running` on every node, self-metrics reach Mimir | ☐ |
