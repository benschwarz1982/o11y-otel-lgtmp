# Windows Server - Instrumentation Guide

[← Back to the template index](../../README.md) - layer 2 of the
[3-layer model](../../schema/README.md) (schema → **platform/
runtime** → application). Template: [`config.yaml`](config.yaml) -
the single canonical file, rendered directly by
`ansible/roles/platform-windows/` (no separate copy under
`ansible/roles/`) - see [README.md's A/B/C
chapters](../../../docs/setup.md#deployment) for the pipeline that runs
it (`deploy-instrumentations:1229-windows-basis`).

## 1. Architecture

```
Windows Server VM
  windowseventlog (System, Application) ──┐
  windowsperfcounters (CPU/Mem/Disk/Net) ──┤
                                            ▼
                         OTel Collector (otelcol-contrib, Windows service)
                         receivers: windowsperfcounters, windowseventlog(x2)
                         processors: memory_limiter, resource/host, batch
                                            │
                                            ▼ OTLP/gRPC, tenant_id header
                                  OTel Gateway (AKS, internal LoadBalancer)
                                            │
                                  Mimir (metrics) / Loki (logs)
```

Same platform-scoped-only principle as the [Linux
template](../1286-linux-basis/) - application/middleware telemetry pushes
straight to the gateway on its own, see
[`instrumentation/middleware/`](../../middleware/).

## 2. Installation

```
https://opentelemetry.io/docs/collector/installation/#windows
otelcol-contrib.exe --config=config.yaml, registered as a Windows service
```

Placeholders to substitute at deploy time (see `config.yaml`'s own
header comment): `<GATEWAY_INTERNAL_IP>`, `<TENANT_ID>` (e.g.
`1229-prod`), `<DEPLOYMENT_ENVIRONMENT>`.

`OS_NAME`/`OS_BUILD` machine environment variables must be set once at
instrumentation time from `Get-CimInstance Win32_OperatingSystem` -
Windows has no `EnvironmentFile`-equivalent to read this from
automatically the way Linux's `/etc/os-release` does (see
`config.yaml`'s own comment).

## 3. Collector Config Walkthrough

- **`windowsperfcounters`**: Processor/Memory/LogicalDisk/Network
  Interface counters.
- **`windowseventlog`** (x2): `System` and `Application` channels -
  `Security` deliberately not included in this demo's template
  (real-world rollouts with Security-channel auditing needs would add
  it, watching for volume - see the [NetApp/Mainframe reference
  guides](../4015-filestorage/) for how much log volume a channel like this can
  generate at real fleet scale).
- **`resource/host`**: `host.name` (`${env:COMPUTERNAME}`),
  `os.type`/`os.name`/`os.version`, plus
  [`schema/core.yaml`](../../schema/core.yaml)'s Core Schema
  attributes - `platform.type` (static), `deployment.environment`
  (per-tenant placeholder). No `platform.vendor` set here (no single
  vendor concept as clear-cut as Linux's distro).
- **`otlp/host`** exporter: `tenant_id` header, same mechanism as
  every other platform - see
  [Multi-Tenancy](../../../docs/setup.md#b9-multi-tenancy-onboarding).

## 4. Validation

```powershell
Get-Service otelcol-contrib
Invoke-WebRequest http://localhost:8888/metrics | Select-String otelcol_process_uptime
```

## 5. Known Pitfalls

Found live during this platform's own rollout - see [README.md's
Known Pitfalls](../../../docs/known-pitfalls.md#known-pitfalls) for the full
write-up:
- **The `resourcedetection` processor's `system` detector doesn't
  populate an OS-release-equivalent attribute on Windows** - unlike
  Linux, where it can be sourced from `/etc/os-release` directly. The
  `Get-CimInstance`-at-setup-time workaround above exists because of
  this.
- **A `#` in a Windows admin password silently broke WinRM
  connections used by this platform's own Ansible rollout**, with a
  completely misleading SSH-related error - see Known Pitfalls for the
  full root cause (an unquoted heredoc + Ansible's INI inventory parser
  treating `#` as a comment marker).

## Rollout Checklist

| Step | Description | Status |
|---|---|---|
| 1 | Install the collector binary, register as a Windows service | ☐ |
| 2 | Set `OS_NAME`/`OS_BUILD` machine env vars from `Get-CimInstance` | ☐ |
| 3 | Render `config.yaml`'s placeholders (`<GATEWAY_INTERNAL_IP>`/`<TENANT_ID>`/`<DEPLOYMENT_ENVIRONMENT>`) | ☐ |
| 4 | Start the service, confirm autostart | ☐ |
| 5 | Validate: self-metrics + a real Event Log entry reach Loki | ☐ |
