# Network Device (SNMP) - Instrumentation Guide

[← Back to the template index](../../README.md) - layer 2 of the
[3-layer model](../../schema/README.md) (schema → **platform/
runtime** → application). Template: [`config.yaml`](config.yaml) - this
system's (1294 Netzwerk Basis) actual live config, read directly by
Terraform (`fleet-1294-netzwerk-basis/main.tf`'s `file()`). Polls a
`snmpd` sidecar in the same pod over real SNMP (v2c), tagged as tenant
`1294-prod` - the SNMP protocol itself is real, only the device behind
it is simulated. [`config-bare.yaml`](config-bare.yaml) is the pre-
instrumentation placeholder `deploy-fleets:1294-netzwerk-basis` ships
first (exports to `debug` only, no telemetry yet) - `var.instrument`
swaps it for `config.yaml`.

For a **real** switch/router/firewall (not this demo's simulated
device): the shape is the same (`snmp` + `syslog` receivers), but a
real device needs `endpoint: udp://<device-ip>:161` instead of
`127.0.0.1` (polled remotely, not from a sidecar in the same pod), a
`syslog` receiver if the device actively pushes syslog (this demo's
device doesn't), and its own SNMP community/version matched to what
the device actually speaks.

## 1. Architecture

```
snmpd sidecar (simulated device, same pod)
  SNMP (polled, real protocol) ──┐
                                  ▼
          OTel Collector (sidecar in the same K8s pod)
          receivers: snmp
          processors: batch, resource
                     │
                     ▼ OTLP/HTTP, tenant_id header
           OTel Gateway → Mimir (metrics)
```

No middleware layer here, unlike Linux/Windows - a network device
never runs an application "on" it, so this collector is platform-
scoped by nature, nothing else to layer on top.

## 2. Installation

Applied by Terraform as this pod's collector ConfigMap
(`fleet-1294-netzwerk-basis/main.tf`) - no manual install. See
[C. Fleets](../../../docs/setup.md#c-fleets-pipeline) for the
`deploy-fleets:1294-netzwerk-basis`/`deploy-instrumentations:1294-
netzwerk-basis` CI jobs that provision/instrument it.

## 3. Collector Config Walkthrough

- **`snmp`**: polls standard MIB-II interface counters (`ifInOctets`/
  `ifInErrors`) via SNMPv2c against the `snmpd` sidecar.
- **`resource`**: `platform.type: network`, `deployment.environment:
  prod` - this schema's Core Schema attributes.
- **`otlphttp`** exporter: `tenant_id: "1294-prod"` header, same
  mechanism as every other platform.

## 4. Validation

```bash
curl -s http://localhost:8888/metrics | grep otelcol_receiver_accepted
```

Query Mimir for `network.io{tenant="1294-prod"}` /
`network.errors{...}` and confirm non-zero values.

## 5. Known Pitfalls

No platform-specific pitfalls found live for this one yet (unlike
Linux/Windows/Kubernetes) - see [README.md's Known
Pitfalls](../../../docs/known-pitfalls.md#known-pitfalls) for the repo-wide list if
one comes up.

## Rollout Checklist

| Step | Description | Status |
|---|---|---|
| 1 | `deploy-fleets:1294-netzwerk-basis` - provisions with `config-bare.yaml` | ☐ |
| 2 | `deploy-instrumentations:1294-netzwerk-basis` - swaps in `config.yaml` | ☐ |
| 3 | Validate: interface counters reach Mimir under `1294-prod` | ☐ |
