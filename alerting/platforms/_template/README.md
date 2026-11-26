# \<Platform Type\> - Alert Rules Template

[← Back to alerting index](../../README.md).

Copy this folder to `alerting/platforms/<system-id>-<your-platform>/`
(or the bare, no-ID form if this platform follows
`instrumentation/platforms/object-storage/`'s own no-ID convention)
when adding alert rules for a new platform type. One `alert-rules.yaml`
per system, using the native Grafana alerting file-provisioning schema
(`apiVersion: 1`, `groups[].rules[]`) - see any real folder here (e.g.
[`1286-linux-basis/`](../1286-linux-basis/)) for the pattern.

Each rule's query stage needs a real `datasourceUid` -
`mimir-<system_id>-<env>` (or `loki-`/`tempo-`) - see
`scripts/provision.py`'s `_render_datasource_configmap()` for where
that uid is set. Set `folder:` to the Demo Use Case title this
platform belongs to (verbatim from `README.md`'s Demo Use Cases
table), not the system's own name - alerts are grouped by
demo-narrative Use Case in Grafana's Alerting UI, not by system.

Rules only - no contact point/notification policy/delivery is
configured anywhere in this repo, see [`alerting/README.md`](../../README.md).

Update `alerting/README.md`'s coverage table with the new entry.
