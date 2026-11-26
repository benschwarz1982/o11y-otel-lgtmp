# Mainframe z/OS - Instrumentation Guide

> ⚠️ **Not part of this demo's live fleet.** Reference only, to
> demonstrate the [3-layer model](../../schema/README.md)
> extends beyond what's actually deployed here -
> `schema/core.yaml` lists `mainframe-zos` under
> `platform_extensions.not_present` for exactly this reason. No
> `config.yaml` in this folder - there is no OTel-community-standard
> config for this platform at all (see below), let alone one this repo
> could ship a working demo of.
>
> ⚠️ **This folder's `1285` prefix is not a system ID** - unlike every
> other numbered `instrumentation/platforms/`/`instrumentation/
> applications/` folder, it doesn't identify a system in this repo's
> fleet (this guide has none - see above); it's illustrative only,
> following the same numbering style as the live platforms for
> consistency (see [`4015-filestorage/`](../4015-filestorage/) for the
> other reference-only guide with the same kind of prefix).

[← Back to the template index](../../README.md)

## 1. Why This Is Different From Every Other Platform Here

z/OS is a closed platform like NetApp, but with one further
difference: there is **no official OTel Collector port for z/OS**, not
even for USS. z/OS telemetry isn't exposed via a modern REST API
either (unlike NetApp) - it's **SMF** (System Management Facility) and
**RMF** (Resource Measurement Facility) records, a proprietary,
record-based format. A direct agent is not an option here the way it
is for Linux/Windows.

## 2. The Established Bridge: IBM Common Data Provider (CDP)

```
z/OS LPAR: SMF/RMF records, OPERLOG
  → IBM Common Data Provider (CDP) - reads SMF/RMF, streams as JSON/Avro
  → Kafka (or Syslog for events only)
  → OTel Gateway (kafkareceiver + transform/mapping)
  → Mimir / Loki
```

CDP is a commercial IBM product - the standard way to get SMF/RMF data
out of z/OS into an open format *before* any OTel layer is involved.
Requires SMF logstreams (not classic datasets) for near-real-time
delivery.

## 3. Sketch: Gateway Receiver + Mapping

```yaml
receivers:
  kafka/zos-smf:
    brokers: ["<KAFKA_BROKER>:9093"]
    topic: zos-smf-raw
    encoding: json

processors:
  transform/zos-smf:
    metric_statements:
      - context: metric
        statements:
          - set(resource.attributes["platform.type"], "mainframe")
          - set(resource.attributes["platform.vendor"], "ibm-zos")
```

The SMF-field-to-OTel-metric-name mapping is the genuinely hard part -
there's no community receiver logic for this the way `hostmetrics`
covers Linux; it needs a hand-written transform/enrichment step, kept
in sync manually.

## 4. Logs/Events: Simpler Alternative

For pure system events (not performance metrics), forwarding z/OS
OPERLOG via syslog to a `syslog` receiver (same receiver type as the
[network device](../1294-netzwerk-basis/)/Kubernetes-agent templates
already use) is far simpler to stand up than the full CDP path, but
carries no performance metrics.

## 5. Known Risk: Volume + Organization

- Active CICS/DB2 regions can produce very large SMF record volumes -
  aggregation belongs as early as possible (ideally in the CDP/Kafka
  step itself), not left for the gateway to absorb raw.
- z/OS systems programming is typically a separate team with its own
  change process - SMF-logstream changes are usually approval-gated;
  this is an organizational dependency to plan for early, not purely a
  Platform Engineering task.

## 6. If This Ever Becomes Real

Would need: confirming whether CDP is already licensed (e.g. for an
existing Splunk integration - reuse rather than a second bridge
technology), the SMF record types actually needed agreed with z/OS
systems programming, a `kafkareceiver` + mapping added to the central
gateway, and removal from `schema/core.yaml`'s
`platform_extensions.not_present` list once genuinely deployed.
