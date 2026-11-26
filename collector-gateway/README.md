# Collector Gateway

[← Back to the main README](../README.md)

This directory is the **one place** in the repo where the central OTel
Collector gateway lives - [`otel-gateway-collector.yaml`](otel-gateway-collector.yaml),
an `OpenTelemetryCollector` CR (OTel Operator). Every platform/
middleware/application in this repo's fleet exports straight to this
one gateway over OTLP/gRPC; it's the single hop between every client
and Mimir/Loki/Tempo.

## Why This Isn't Under `instrumentation/`

[`instrumentation/`](../instrumentation/)'s 3-layer model (schema →
platform/runtime → application) is specifically about **shaping**
telemetry - each layer sets its own resource attributes
(`platform.type`, `service.name`, `app.owner`, ...) for exactly one
system. The gateway doesn't shape anything - it receives telemetry
every platform/app has already shaped, and **routes** it (tenant
isolation via the `headers_setter` extension's `X-Scope-OrgID`
header, onboarding-tenant allowlist enforcement, cardinality
filtering before Mimir) to the right backend. It's shared
infrastructure serving the whole fleet at once, not a template any
one platform/middleware/application extends.

## Why This Isn't Under `k8s/`

It used to be (`kubernetes/collectors/otel-gateway-collector.yaml`).
[`k8s/`](../k8s/) is organized by **deployment
mechanism** - everything there is applied as a Kubernetes object. The
gateway happens to also be a Kubernetes object for the same reason,
but grouping it there reads as "this belongs to the Kubernetes
*platform*" - it doesn't; it serves Linux/Windows VMs and a network
device just as much as it serves anything running on Kubernetes.
Giving it its own top-level home removes that ambiguity instead of
just documenting around it - the same reasoning that already pulled
dashboards/datasources/the Kubernetes-platform's own agent config out
from under `kubernetes/` too, each to a home named after what it
*is* rather than how it's deployed
([`dashboards/`](../dashboards/), [`datasources/`](../datasources/),
[`instrumentation/platforms/4087-container-platform/`](../instrumentation/platforms/4087-container-platform/)).
What's left under `k8s/` (`ingress/` - cert-manager/Traefik
CRDs) is different: ingress routing is inherently tied to *this*
cluster, not conceptually independent of it the way all of the above
are.

## Deployed By

`terraform/environments/tenants/` (`null_resource` + `kubectl apply`,
not a typed `kubernetes_manifest` - that CR kind hits a reproduced
`hashicorp/kubernetes` provider bug, see [README.md's Known
Pitfalls](../README.md#known-pitfalls)), run by the `tenants:rollout`
CI job on every onboarding-approval merge. Its tenant allowlist
(`filter/reject_unknown_tenants`) is kept in sync with currently
onboarded tenants by [`scripts/provision.py`](../scripts/provision.py)'s
`update_gateway_tenant_allowlist()` - see that function's own
docstring for why this file, specifically, needs to change on every
onboard/offboard, not just when someone hand-edits the collector
config itself.

See [Multi-Tenancy](../README.md#b9-multi-tenancy-onboarding) for the
full tenant-routing write-up, and [B10. Telemetry
Schema](../README.md#b10-telemetry-schema) for the Cardinality Rule
this file's own filter/transform processors enforce.
