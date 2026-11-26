# \<Application Type\> - Alert Rules Template

[← Back to alerting index](../../README.md).

Copy this folder to `alerting/applications/<system-id>-<your-app>/`
when adding alert rules for a new application. One `alert-rules.yaml`
per system, using the native Grafana alerting file-provisioning schema
(`apiVersion: 1`, `groups[].rules[]`) - see any real folder here (e.g.
[`4720-otel-astronomy-shop/`](../4720-otel-astronomy-shop/)) for the pattern.

Each rule's query stage needs a real `datasourceUid` -
`mimir-<system_id>-<env>` (or `loki-`/`tempo-`) - see
`scripts/provision.py`'s `_render_datasource_configmap()` for where
that uid is set. Set `folder:` to the Demo Use Case title this
application belongs to (verbatim from the Use Cases table in
`docs/demo.md`), not the system's own name - alerts are grouped by
demo-narrative Use Case in Grafana's Alerting UI, not by system.

## Middleware/Runtime-Owned Conditions

If this application's alert condition is really about a middleware/
runtime it exclusively owns (Tomcat, PostgreSQL, ...), put that rule
directly in this same file, under this application's own tenant - same
"Middleware/runtime tenants" rule as everywhere else in this repo
(see [Multi-Tenancy](../../../docs/setup.md#b9-multi-tenancy-onboarding)):
a runtime used by exactly one application reports under that
application's own tenant, never a separate one, so it never has its
own `datasourceUid` to alert against. There is deliberately no
`alerting/middleware/` layer for this reason.

Rules only - no contact point/notification policy/delivery is
configured anywhere in this repo, see [`alerting/README.md`](../../README.md).

Update `alerting/README.md`'s coverage table with the new entry.
