# NetApp ONTAP - Instrumentation Guide

> ⚠️ **Not part of this demo's live fleet.** Reference only, to
> demonstrate the [3-layer model](../../schema/README.md)
> extends beyond what's actually deployed here -
> `schema/core.yaml` lists `netapp` under
> `platform_extensions.not_present` for exactly this reason. No
> `config.yaml` in this folder (unlike the live-demo platforms) since
> there's nothing to deploy in this repo. `instrumentation/platforms/object-
> storage/config.yaml` has a placeholder `httpcheck` poll gesturing at
> this, not a real integration.
>
> ⚠️ **This folder's `4015` prefix is not a system ID** - unlike every
> other numbered `instrumentation/platforms/`/`instrumentation/
> applications/` folder, it doesn't identify a system in this repo's
> fleet (this guide has none - see above). The actual system 4015
> ("Filestorage") is [`object-storage/`](../object-storage/), a
> different, unrelated, live technology (Azure Blob object storage,
> not NetApp/NAS file storage) - don't confuse the two.

[← Back to the template index](../../README.md)

## 1. Why This Is Different From the Live-Demo Platforms

ONTAP is a closed storage-OS appliance - no native OTel collector
agent can run on the cluster itself, unlike Linux/Windows. The
standard community/NetApp-provided path:

```
ONTAP Cluster (REST/ZAPI) → NetApp Harvest (poller, separate host)
  → Prometheus exposition (:12990/metrics)
  → OTel Collector (prometheus receiver) → Mimir/Loki/Tempo
```

Harvest is NetApp's own open-source Go tool - it polls the ONTAP REST
API on a schedule and exposes Prometheus-format metrics; it does not
run on the cluster, but on a separate host/container.

## 2. Architecture Decision: Gateway, Not Agent

Since Harvest already exposes Prometheus format, an OTel Collector
gateway instance scrapes it via a `prometheusreceiver` - fitting the
same agent→gateway pattern the live-demo platforms use, rather than a
raw Prometheus-scrape bypass of the OTel pipeline entirely.

## 3. Sketch: Gateway Scrape Config

```yaml
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: netapp-harvest
          scrape_interval: 60s
          static_configs:
            - targets: ["<HARVEST_HOST>:12990"]

processors:
  resource:
    attributes:
      - key: platform.type
        value: netapp
        action: upsert
      - key: platform.vendor
        value: netapp
        action: upsert
```

A dedicated **read-only** ONTAP monitoring user (not an admin account)
is the expected setup for Harvest, same "least privilege" principle
this repo already applies to its own bootstrap Service Principals (see
[Known Pitfalls](../../../README.md#known-pitfalls)).

## 4. Logs/Events

ONTAP has no journald/filelog equivalent - events come via **EMS**
(Event Management System), forwarded as syslog to a collector's
`syslog` receiver (same receiver type this repo's [network device
template](../1294-netzwerk-basis/) already uses).

## 5. Known Risk: Cardinality

Harvest exposes very granular metrics (per volume, per LUN, per
aggregate) - the same class of risk this repo already hit for real
with the `processes` scraper on the [Linux
template](../1286-linux-basis/#5-known-pitfalls) (unbounded per-item series).
Any real rollout needs metric-relabeling or Harvest-side object
filtering before this data reaches Mimir.

## 6. If This Ever Becomes Real

Would need: a Harvest host/container provisioned, a read-only ONTAP
monitoring role, a `prometheusreceiver` added to the central gateway
(`collector-gateway/otel-gateway-collector.yaml`), cardinality
filtering, and removal from `schema/core.yaml`'s
`platform_extensions.not_present` list once it's genuinely deployed.
