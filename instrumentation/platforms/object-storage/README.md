# Object Storage - Instrumentation Guide

[← Back to the template index](../../README.md) - layer 2 of the
[3-layer model](../../schema/README.md) (schema → **platform/
runtime** → application). Template: [`workload.py`](workload.py) -
this system's (4015 Filestorage) actual live workload, read directly
by Terraform (`fleet-4015-filestorage/main.tf`'s `file()`). Uploads/
downloads/lists/deletes small blobs on a loop against a **real** Azure
Blob Storage account, emitting its own telemetry directly via the OTel
SDK (there's no built-in OTel instrumentation for the Azure SDK) - the
storage account is real, only the traffic driving it is synthetic.

For a **real**, already-in-production Azure Storage Account (not a
synthetic workload generating its own traffic): there's no application
to instrument at all - what you'd actually deploy is a standalone
collector polling Azure Monitor's own metrics for that account, via
the `azuremonitor` receiver (not part of this repo, since this demo's
own object-storage telemetry comes from the workload itself, not an
external poll) - `platform.vendor: azure` either way. See [the NetApp
reference guide](../4015-filestorage/) if the object storage in question is
NetApp ONTAP rather than Azure Blob Storage - a materially different
integration (no OTel receiver, Harvest as the standard bridge instead).

## 1. Architecture

```
Real Azure Blob Storage Account
        ▲
        │ upload/download/list/delete (real API calls)
        │
Synthetic Python workload (workload.py, in-cluster)
  OTel SDK directly (spans/metrics/logs on every operation)
        │
        ▼ OTLP/HTTP, tenant_id header
   OTel Gateway → Mimir (metrics) / Tempo (traces) / Loki (logs)
```

No middleware layer here, unlike Linux/Windows - no application ever
runs "on" a storage backend the way it runs on a VM.

## 2. Installation

Applied by Terraform as this pod's ConfigMap
(`fleet-4015-filestorage/main.tf`) - no manual install. See
[C. Fleets](../../../docs/setup.md#c-fleets-pipeline) for the
`deploy-fleets:4015-filestorage`/`deploy-instrumentations:4015-
filestorage` CI jobs.

## 3. Workload Walkthrough

- **`Resource.create({...})`**: `service.name`/`service.namespace`,
  plus `platform.type: object-storage` - this schema's Core Schema
  attributes, set directly via the Python SDK (no separate collector
  config to layer them onto - the workload exports OTLP itself).
- **Traces**: one span per blob operation (`blob.upload`/`blob.download`/
  `blob.list`), tagged with `blob.name`/`blob.size_bytes`.
- **Metrics**: `storage.operations` (counter), `storage.operation.bytes`
  (histogram), `storage.container.bytes`/`storage.container.blob_count`
  (gauges, updated on every `list` cycle - live growth tracking for
  anomaly detection).

## 4. Validation

Query Mimir for storage-operation metrics under tenant `4015-prod`,
and Tempo for the workload's own storage-operation traces.

## 5. Known Pitfalls

No platform-specific pitfalls found live for this one yet - see
[README.md's Known Pitfalls](../../../docs/known-pitfalls.md#known-pitfalls) for
the repo-wide list if one comes up.

## Rollout Checklist

| Step | Description | Status |
|---|---|---|
| 1 | `deploy-fleets:4015-filestorage` - provisions the Storage Account, `var.instrument=false` | ☐ |
| 2 | `deploy-instrumentations:4015-filestorage` - `var.instrument=true`, workload starts emitting telemetry | ☐ |
| 3 | Validate: real metrics/traces reach Mimir/Tempo under `4015-prod` | ☐ |
