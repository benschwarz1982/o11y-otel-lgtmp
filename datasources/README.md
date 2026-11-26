# Datasources

[← Back to the main README](../README.md) - see [B6. Per-Tenant
Datasources/Dashboards](../README.md#b6-per-tenant-datasourcesdashboards)
for the full write-up.

One Grafana datasource ConfigMap per onboarded tenant (Mimir/Loki/Tempo
triplet, pinned to that tenant via the `X-Scope-OrgID` header), plus a
permanent tombstone for every tenant that's ever been offboarded since -
Grafana's file-based datasource provisioning is add/update-only, so a
tombstone (`deleteDatasources`) is the only way to actually remove one,
and it has to stay in place forever once written (see
`scripts/provision.py`'s `_render_tombstone_configmap()` for why).

## Filenames: `<system_id>-<slug-of-name>-<env>.yaml`

Matches the `<id>-<name>` convention
[`instrumentation/applications/`](../instrumentation/applications/)
and [`dashboards/`](../dashboards/)'s own generated `<env>/` output
both use - e.g. `4721-kundenverwaltung-prod.yaml`. The slug is
cosmetic only: nothing re-derives a tenant ID by parsing the filename,
`scripts/provision.py` matches each existing file back to its tenant
by reading its own `metadata.name`
(`grafana-datasource-<system_id>-<env>`) instead - safe because a
system's `name` is immutable once onboarded (see the self-service
form's own "Type/name can't be changed here" hint), so a tenant's
filename never needs to change mid-lifetime the way it could if the
slug were load-bearing.

## Why No `templates/`/`platforms`/`middleware`/`applications` Split

Unlike [`dashboards/`](../dashboards/), a datasource ConfigMap has no
per-platform-type *shape* - every file is structurally identical (a
Mimir/Loki/Tempo triplet plus a tenant header), whether the tenant
behind it is a platform or an application. There's nothing to
template-catalog, so this stays one flat directory.

## Why This Isn't Under `k8s/`

Same reasoning as [`dashboards/`](../dashboards/README.md) and
[`collector-gateway/`](../collector-gateway/README.md) -
[`k8s/`](../k8s/) is organized by deployment mechanism,
not by what its contents actually are.
