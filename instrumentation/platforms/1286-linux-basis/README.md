# Linux (RHEL-like) - Instrumentation Guide

[← Back to the template index](../../README.md) - layer 2 of the
[3-layer model](../../schema/README.md) (schema → **platform/
runtime** → application). Template: [`config.yaml`](config.yaml) -
the single canonical file, rendered directly by
`ansible/roles/platform-linux/` (no separate copy under
`ansible/roles/`) - see [README.md's A/B/C
chapters](../../../docs/setup.md#deployment) for the pipeline that runs
it (`deploy-instrumentations:1286-linux-basis`).

## 1. Architecture

```
┌─────────────────────────────────────────┐
│  RHEL Host (Linux Basis Platform)        │
│                                           │
│  ┌──────────────┐  ┌───────────────────┐│
│  │ journald      │  │ hostmetrics        ││
│  │ (systemd logs)│  │ (CPU/Mem/Disk/Net) ││
│  └──────┬───────┘  └─────────┬─────────┘│
│         │                    │           │
│         ▼                    ▼           │
│  ┌─────────────────────────────────────┐│
│  │  OTel Collector (Contrib, Agent)     ││
│  │  receivers: journald, hostmetrics    ││
│  │  processors: memory_limiter,         ││
│  │              resource/host, batch    ││
│  └───────────────────┬───────────────────┘│
└──────────────────────┼──────────────────┘
                        │ OTLP/gRPC, tenant_id header
                        ▼
          OTel Gateway (AKS, internal LB)
                        │
              ┌─────────┴─────────┐
              ▼                   ▼
        Mimir (Metrics)      Loki (Logs)
```

One collector per VM, platform-scoped only - application/middleware
telemetry deliberately isn't this template's concern (every app on
this VM pushes its own OTLP straight to the gateway with its own
tenant_id, see [`instrumentation/middleware/`](../../middleware/)).

## 2. Installation

Two valid paths, shown below - pick whichever fits your environment.
**This demo's own Ansible role uses neither exactly**: it downloads
the RPM directly from GitHub Releases (no internal repo involved) and
installs that local file with `dnf install --nogpgcheck ./otelcol-contrib.rpm`
- closest to 2.2 in spirit, minus the repo assumption. See
[ansible/roles/platform-linux/tasks/main.yml](../../../ansible/roles/platform-linux/tasks/main.yml)
for the exact live commands.

### 2.1 Binary Installation (recommended for a server fleet, no internal repo needed)

```bash
# Set the version
OTEL_VERSION="0.166.0"
ARCH="amd64"   # or arm64

curl -L -o /tmp/otelcol-contrib.tar.gz \
  "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_${ARCH}.tar.gz"

sudo mkdir -p /opt/otelcol-contrib
sudo tar -xzf /tmp/otelcol-contrib.tar.gz -C /opt/otelcol-contrib

sudo useradd --system --no-create-home --shell /usr/sbin/nologin otel
sudo mkdir -p /etc/otelcol-contrib /var/log/otelcol-contrib
sudo chown -R otel:otel /opt/otelcol-contrib /var/log/otelcol-contrib
sudo cp config.yaml /etc/otelcol-contrib/config.yaml
```

No systemd unit ships with the tarball - see [2.4](#24-systemd-unit-template)
below, required before this path's service will actually start.

### 2.2 RPM Installation (alternative, if an internal repo is available)

```bash
sudo dnf install -y otelcol-contrib-0.166.0-1.x86_64.rpm
sudo cp config.yaml /etc/otelcol-contrib/config.yaml
```

Simpler than 2.1 when available - package manager handles the
systemd unit and the `otelcol-contrib` system user itself (see below),
and upgrades become a normal `dnf update`. `--nogpgcheck` (this demo's
own Ansible role: `disable_gpg_check: true`) is only needed for the
2.1-style direct-from-GitHub RPM this demo actually installs - the
upstream release RPM isn't GPG-signed with a key this environment has
imported; drop the flag once pulling from a real internal repo that
signs its own packages, or once the OpenTelemetry release signing key
is imported.

Placeholders to substitute at deploy time (see `config.yaml`'s own
header comment): `<GATEWAY_INTERNAL_IP>`, `<TENANT_ID>` (this VM's own
platform tenant, e.g. `1286-prod`), `<DEPLOYMENT_ENVIRONMENT>`.

Two one-time setup steps, both required before the service starts
cleanly regardless of which install path above was used (see
`config.yaml`'s own installation comment for the exact commands) -
substitute the collector's actual service user below (`otel` for 2.1,
`otelcol-contrib` for 2.2/this demo's own RPM install, auto-created by
the package):
- A systemd override providing `HOSTNAME`/`NAME`/`VERSION_ID` -
  systemd services don't inherit shell environment variables, and
  `/etc/os-release` is already in `EnvironmentFile` syntax, reused
  directly rather than parsed.
- The service user added to the `systemd-journal` group, or the
  journald receiver fails with insufficient-permissions errors.

### 2.3 SELinux Note

If SELinux is `enforcing`: the collector binary and log access may
need their own context. Commands below are written for 2.1's
paths/user - substitute the RPM's own binary path (typically
`/usr/bin/otelcol-contrib`) and its own `otelcol-contrib` user for 2.2.
**Not applied by this demo's own Ansible role** - neither this guide
nor `ansible/roles/platform-linux/` runs these today. If a real RHEL
rollout runs SELinux in `enforcing` mode and hits denials, that's a
genuine gap in this template, not a deliberately-omitted step - add
this (and a matching Known Pitfalls entry once actually hit) rather
than assuming it's already covered.

```bash
sudo semanage fcontext -a -t bin_t "/opt/otelcol-contrib/otelcol-contrib"
sudo restorecon -v /opt/otelcol-contrib/otelcol-contrib
# journald access: add the service user to the 'systemd-journal' group
sudo usermod -aG systemd-journal otel
```

### 2.4 Systemd Unit (Template)

Only needed for 2.1 - the RPM (2.2, and this demo's own live install)
ships its own unit and auto-creates its own `otelcol-contrib` system
user, which is why `ansible/roles/platform-linux/tasks/main.yml` has
no separate systemd-unit-authoring task at all, only the HOSTNAME/
os-release override on top of it (see the two one-time setup steps
above).

`/etc/systemd/system/otelcol-contrib.service`:

```ini
[Unit]
Description=OpenTelemetry Collector Contrib
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=otel
Group=otel
ExecStart=/opt/otelcol-contrib/otelcol-contrib --config=/etc/otelcol-contrib/config.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
StandardOutput=append:/var/log/otelcol-contrib/otelcol.log
StandardError=append:/var/log/otelcol-contrib/otelcol.log

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/otelcol-contrib
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now otelcol-contrib
sudo systemctl status otelcol-contrib
```

## 3. Collector Config Walkthrough

- **`hostmetrics`**: CPU/memory/disk/filesystem/network/load -
  deliberately *not* the `processes` scraper (see [Known
  Pitfalls](#5-known-pitfalls) below).
- **`journald`**: this platform's log source - RHEL-native, not
  classic syslog files.
- **`resource/host`**: `host.name`, `service.name`/`service.namespace`,
  `os.type`/`os.name`/`os.version` (real distro/release, for the OS
  Release panels), plus [`schema/core.yaml`](../../schema/core.yaml)'s
  Core Schema attributes - `platform.type`/`platform.vendor` (static),
  `deployment.environment` (per-tenant placeholder).
- **`otlp/host`** exporter: `tenant_id` header - this is how
  [Multi-Tenancy](../../../docs/setup.md#b9-multi-tenancy-onboarding)
  routes this VM's data to its own tenant.

## 4. Validation

```bash
systemctl status otelcol-contrib
curl -s http://localhost:8888/metrics | grep otelcol_process_uptime
logger "otel-test-event-$(date +%s)"
# then search Loki for "otel-test-event" in Grafana > Explore
```

Two more checks, useful when the above doesn't turn up the problem:
- **Network path to the gateway** - this template talks to exactly one
  place, Traefik's internal OTLP mTLS LoadBalancer IP (no separate
  per-signal endpoints, unlike a direct-to-backend setup):
  `nc -zv <traefik_otlp_ip> 14317`.
- **What's actually being sent**, without waiting for it to show up in
  Grafana - temporarily add a `debug` exporter to `service.pipelines.*`
  and rerun the collector by hand in the foreground:
  `otelcol-contrib --config=/etc/otelcol-contrib/config.yaml`. Revert
  before leaving it running - `debug` isn't part of this template's
  own pipelines.

## 5. Known Pitfalls

Both found live during this platform's own rollout - see
[README.md's Known Pitfalls](../../../docs/known-pitfalls.md#known-pitfalls) for
the full write-up of each:
- **"error creating AttrProc" on startup**: `${env:HOSTNAME}` empty
  because systemd doesn't inherit shell env vars - fixed by the
  systemd override in step 2 above.
- **"No journal files were opened due to insufficient permissions"**:
  `otelcol-contrib` needs the `systemd-journal` group membership from
  step 2.
- **Unbounded cardinality from the `processes` scraper**: ~130
  processes on a demo VM alone pushed the tenant over its
  `ingestion_burst_size`, causing the gateway to drop data for
  everything sharing that export queue - this template deliberately
  omits it.

## Rollout Checklist

| Step | Description | Status |
|---|---|---|
| 1 | Install the collector RPM (`dnf install --nogpgcheck`) | ☐ |
| 2 | Systemd override (`HOSTNAME`/os-release) + `systemd-journal` group | ☐ |
| 3 | Render `config.yaml`'s placeholders (`<GATEWAY_INTERNAL_IP>`/`<TENANT_ID>`/`<DEPLOYMENT_ENVIRONMENT>`) | ☐ |
| 4 | Enable + start the service | ☐ |
| 5 | Validate: self-metrics + a real log line reach Loki | ☐ |
