# Alerting

[← Back to the main README](../README.md) - see [B11.
Alerting](../docs/setup.md#b11-alerting) for the full write-up.

Grafana Unified Alerting **rules only** - no contact points, no
notification policies, no delivery channel (SMTP/Slack/etc.) is
configured anywhere in this repo. A firing/pending/normal alert is
only ever visible on Grafana's own Alerting page - nothing gets sent
anywhere. Same ConfigMap+sidecar auto-discovery mechanism as
[`dashboards/`](../dashboards/)/[`datasources/`](../datasources/)
(`sidecar.alerts`, label `grafana_alert: "1"` - see
[`helm/values/grafana-values.yaml`](../helm/values/grafana-values.yaml)),
applied by `tenants:rollout`
(`terraform/environments/tenants/main.tf`'s
`kubernetes_config_map.alert_rules`) - a fixed set tied to this demo's
4 Use Cases, not an onboarding-driven fan-out the way per-tenant
datasources/dashboards are (these 4 files are hand-authored, not
generated from a manifest by `scripts/provision.py`). Content and
deployment location are different axes, though: these rules are pinned
to specific onboarded systems (1229/1286/4720), so *deploying*
them travels with `tenants:rollout` rather than
`deploy:observability-stack` - found live that decoupling the two
meant an alert-rules.yaml edit could go stale indefinitely, since
nothing about the routine onboarding pipeline would ever prompt
re-running the separate, rarely-used full-platform-redeploy job.

## One Alert Per Demo Use Case

Trimmed to exactly the 4 Use Cases in `README.md`'s own Use Cases
table - 1294/4015/4087/4722 no longer anchor a Use Case of their own
(after the Demo Runbook redesign) and their alert rules were deleted
outright rather than kept around unused, matching this repo's own
"weniger ist mehr" call. UC2 has been redesigned twice: originally
4721 (Postgres connection usage + a since-deleted app-latency rule -
found live it structurally couldn't fire, no connection pool/retry
logic in 4721's app code, so external connection pressure never
elevates request latency there), then found to read too similarly to
UC1 (also a platform, also a metrics-only alert) and replaced outright
with 1229 (Windows Service Crash, a Logs signal instead) - see
[`platforms/1229-windows-server-basis/alert-rules.yaml`](platforms/1229-windows-server-basis/alert-rules.yaml)'s
own header comment for that mechanism's full history. UC4 (Object
Storage Usage, 4015) was dropped outright rather than replaced -
`platforms/object-storage/alert-rules.yaml` was deleted, and the
former UC5 (Multi-Tenancy: Ingestion Budget Enforcement) moved up to
fill the UC4 slot; 4015 itself stays onboarded, it just has no alert
of its own anymore.

| Use Case | Rule file(s) | Grafana folder |
|---|---|---|
| UC1 - Linux CPU Saturation | `platforms/1286-linux-basis/` | `1286` |
| UC2 - Windows Service Crash | `platforms/1229-windows-server-basis/` (Print Spooler crash) | `1229` |
| UC3 - Kubernetes Microservices | `applications/4720-otel-astronomy-shop/` | `4720` |
| UC4 - Multi-Tenancy: Ingestion Budget Enforcement | `shared/operator-ingestion-budget.yaml` (cross-tenant, `4711-prod` is this UC's demo tenant - see the main README's Runbook) | `shared` |

`folder:` is set inside each rule file's own YAML content (not a
Kubernetes label/annotation the way a dashboard's `grafana_folder`
annotation is) - a single level, just each rule's own system_id
(`1286`), the same folder its dashboard lives in, rather than a folder
named after the Use Case. A two-level `<env>/<system_id>` scheme was
tried first and reverted - Grafana's dashboard file-provisioner only
reliably supports one folder level (confirmed live, a known open
upstream limitation,
[grafana/grafana#107158](https://github.com/grafana/grafana/issues/107158)),
so environment moved to an in-dashboard variable instead of a folder
level (see the main README's
[B8](../docs/setup.md#b8-per-system-dashboards-onboarding)) and alert
folders followed suit for consistency. `shared` (UC4, cross-tenant, no
single owning system) stays flat and top-level, same folder its own
dashboard (`dashboards/shared/operator-tenant-budget.json`) lives in.

4087 (the AKS cluster itself) used to sit alongside 4720 in UC3's own
`README.md` table row - UC3 is now scoped to 4720 only (Application
Engineer audience, application-side signals only), so 4087 no longer
anchors any Use Case, same as 1294/4015/4722. A future 4087 alert
(pod restart count, node memory pressure) is a natural next addition,
not a gap left by this change.

**Every rule needs an explicit `reduce` stage, easy to miss**: found
live while verifying all of this actually fires - a query stage
(`refId A`, `range: true`) can't feed straight into a `threshold`
stage, Grafana errors with "looks like time series data, only reduced
data can be alerted on" (or, for a multi-series query, "frame cannot
uniquely be identified by its labels"). Every rule here has a
`refId B` (`type: reduce`, `reducer: last`) between the query and the
threshold - see `platforms/1286-linux-basis/alert-rules.yaml` for the
canonical shape to copy when adding a new rule.

**A file disappearing doesn't remove its rule from Grafana, but there
is a working fix**: unlike dashboards (which do track file deletions),
deleting an alert rule's source ConfigMap/file leaves the rule
provisioned in Grafana's own alerting store - confirmed live (file
removed, sidecar synced, even a full Grafana pod restart didn't clear
it). This is a real, currently-open upstream bug
(`grafana/grafana#103597`) - the provisioning API's own delete
endpoint unconditionally rejects file-provisioned rules
(`cannot delete with provided provenance '', needs 'file'`,
`X-Disable-Provenance` doesn't help). The 4 rules removed in the Demo
Runbook redesign (1229/1294/4711/4722) were left as harmless orphans in
Grafana's own store at the time - they kept evaluating and erroring
silently under their old folder names, didn't appear anywhere in the
new 5-UC folders, and blocked nothing. Same category of issue as the
one permanently-stuck dashboard already documented in the main
README's Known Pitfalls.

A real fix was found and verified live later, when UC4's own alert was
replaced (the old discard-count rule for the pre-redesign UC4, see
this file's git history): Grafana's file-provisioning format supports
a top-level `deleteRules: [{orgId, uid}]` key that the sidecar honors
as an actual, permanent delete - unlike the API endpoint above. Applied
by pushing a temporary ConfigMap (labeled `grafana_alert: "1"` so the
sidecar picks it up) whose only content is a `deleteRules` block naming
the orphaned rule's `uid`, waiting a few seconds for the sidecar to
sync (confirmed via a 404 on that uid), then deleting the temporary
ConfigMap again. The orphans left over from the original 4-rule
cleanup above were never revisited with this technique since they're
harmless, but any future orphan should be cleared this way instead of
left in place.

**Confirmed live: this bug also applies to a single rule removed from
a file that itself stays present**, not just a whole file
disappearing - 4721's own former latency rule (removed above, one of
two rules in that file) is the 5th such orphan, still evaluating
(`state: inactive`, since its underlying condition genuinely never
fires) under its own stuck `folderUID` - originally the same one the
Postgres-connections rule lived in too, but **a `folder:` rename in
the YAML moves the live rule to a brand-new folder rather than
renaming the existing one in place** (confirmed live: renaming UC2's
folder string left the orphan behind in the old
`UC2 - Application Performance (Java + DB)` folder while the real
rule moved to a freshly-created `UC2 - Database Connection
Saturation` one - the old folder is now permanently stuck too,
undeletable while it still holds the orphan,
`{"messageId":"folder.not-empty"}`). Any future UC folder rename will
leave the same kind of stranded, now-permanently-empty-except-for-the-
orphan old folder behind wherever an orphan already lives there. The
orphan itself keeps showing up on the Alerting page under its own old
`UC2 - Application Performance (Java + DB)` folder, permanently
`inactive`, separate from the real rule's new folder - worth knowing
before a live demo so it doesn't get mistaken for a second,
currently-broken alert.

Most of the above (this section) describes the *prior* AKS
cluster/Grafana instance, since destroyed and recreated from scratch -
none of those specific orphans/stuck folders exist on the current live
instance, since nothing was ever provisioned there under the old flat
`UC1..UC5` folder names to begin with (the table above reflects the
current single-level scheme, applied fresh - see the note above it for
why an interim `<env>/<system_id>` two-level attempt was reverted).

**Confirmed live again on this current instance**, though, when UC2
moved from 4721 (Postgres connections) to 1229 (Windows Service Crash)
and `alerting/applications/4721-kundenverwaltung/alert-rules.yaml` was
deleted outright: `alert-4721-postgres-connections-high` is a 6th
orphan, `state: inactive`/`health: ok` (its query still resolves fine,
just genuinely below threshold - 4721 still has a real Postgres
connection, nothing deliberately spikes it anymore). Unlike the
previous 5, this one sits in the **same** `4721` folder its own
dashboard still legitimately uses (not a separately stranded old
folder) - the folder itself isn't stuck/undeletable this time, since
this was a rule deletion, not a `folder:` rename. Deleting an alert
rule's file here always needs the same manual follow-up: confirm via
`GET /api/v1/provisioning/alert-rules` that nothing is left pointing at
the removed uid, since Grafana's own store won't reflect the deletion
on its own - there's still no working fix once it does, just live with
it.

**Confirmed live**: the same happened to `alert-4015-storage-errors`
after `platforms/object-storage/alert-rules.yaml`'s deletion (dropping
UC4 outright, see above) rolled out via `tenants:rollout` - a 7th
orphan, `state: inactive`/`health: nodata`, still sitting in the same
`4015` folder its own dashboard still legitimately uses, same category
as the 4721 one above.

## Why No `middleware/` Layer

Unlike `instrumentation/middleware/` (reusable, tenant-independent
config templates), an alert rule always needs a concrete
`datasourceUid` for one specific tenant - there's no such thing as a
"generic Tomcat alert rule" independent of which application's tenant
it queries. Per this repo's own "Middleware/runtime tenants" rule (see
[Multi-Tenancy](../docs/setup.md#b9-multi-tenancy-onboarding)), a
middleware/runtime's alert condition (e.g. Tomcat, PostgreSQL) would
live directly in its owning application's own `alert-rules.yaml`, not
a separate `middleware/` one - no such rule exists live in this repo
right now (4721's own former Postgres-connections rule was this
scenario's example until UC2 moved to 1229; the principle stands
either way). No `middleware/_template/` exists here for the same
reason.

## Explicit `datasourceUid`s Required

Every query stage references a real Mimir/Loki datasource `uid`, not a
name - Grafana auto-generates a uid non-deterministically otherwise,
which this independently-authored YAML couldn't reliably reference.
[`helm/values/grafana-values.yaml`](../helm/values/grafana-values.yaml)'s
static `Mimir-anonymous` gets `uid: mimir-anonymous`; every per-tenant
datasource `scripts/provision.py` generates gets
`uid: <mimir|loki|tempo>-<tenant_id>` (e.g. `mimir-4711-prod`) - see
that script's `_render_datasource_configmap()`.

## Not Live Until Onboarded

An alert rule's `datasourceUid` (e.g. `mimir-1286-prod`) only resolves
once that tenant's own datasource has actually been provisioned by
`tenants:rollout` - a rule committed for a system that isn't (yet)
onboarded just evaluates as NoData/Error until it is, the same as any
dashboard/instrumentation template for a not-yet-onboarded system.
All 4 rule groups these files target are, as of this repo's last full
onboarding pass, live - verified directly via Grafana's own Alerting
page (`health: ok`).

## Onboarding a New Platform/Application

Start from [`platforms/_template/`](platforms/_template/) or
[`applications/_template/`](applications/_template/).
