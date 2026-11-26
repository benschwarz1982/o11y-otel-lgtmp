# Platform Features

## Platform Features from the Requirements Review

Built for the gaps found against a requirements catalog (G02-G15;
G05, G07, G13 and G14 were dropped as out of scope for the demo).

### Masking (G02, FR-05)

The gateway's `transform/redact` processor masks e-mail addresses,
IBANs, AHV numbers, credit card numbers (by IIN prefix and length - OTTL
can't run a Luhn check), bearer tokens, credentials in URLs and
`password=`/`token:`-style assignments in every tenant's log bodies
(string bodies and the top-level values of structured bodies), log
attributes and span (event) attributes, before anything is stored.
Attributes whose *name* marks a credential (`password`, `api_key`,
`authorization`, `cookie`, ...) are deleted outright. Values nested
deeper than one level are not reached (OTTL's replace functions don't
recurse).
The catalog is `REDACTION_BASE` in `scripts/provision.py`; a system adds
its own rules in its manifest (`redaction.patterns`, RE2 regex, replaced
by `<redacted:NAME>`, checked for RE2 compatibility by
`validate-manifests` - example: 4721 masks the customer name in its
"Created customer" log line). Metrics are not masked - their attributes
are labels, which the Cardinality Rule keeps free of identifiers.
Test patterns: `scripts/testdata/redaction-samples.yaml`, run with
`scripts/test-redaction.py` (local, needs docker - runs the generated
processor in the gateway's own collector image).

### SLOs (G03, FR-10)

SLOs are OpenSLO v1 files under `slo/<tenant>/` (examples: 4721
Kundenverwaltung 99.5% successful operations, 4720 checkout 99%).
`scripts/generate-rules.py` converts them to OpenSLO v1alpha (the only
version Sloth reads), lets Sloth (v0.16.0, in the CI image) generate the
recording rules and adds multiwindow, multi-burn-rate alerts
(`SLOFastBurn` 14.4x/6x, `SLOSlowBurn` 3x/1x) plus `SLONoData`. The
result, `rules/<tenant>/slo.yaml`, is committed and loaded into the
Mimir ruler. **Missing data is never counted as success** (nor is zero
traffic, whose SLI is 0/0 = NaN): it fires
`SLONoData`, sets the system's status to "unknown" and lowers
`slo:data_coverage:ratio_30d`. Dashboard: *Operator: SLO Overview*
(pick the tenant's Mimir data source).

### Baselines, Anomalies and Calendar (G04, FR-06)

`rules/4721-prod/baseline.yaml` (hand-written, template for other
systems): Kundenverwaltung's throughput against the same hour of the
week over the last three weeks, read from the raw span metrics. Two
levels above and below the baseline (warning: max(30%, 2 stddev),
critical: max(60%, 4 stddev)) plus an absence alert. Lower bounds only
alert during business hours; nothing alerts in the maintenance window.
The calendar is a set of recording rules (`calendar:business_hours:bool`,
`calendar:maintenance_window:bool`, Europe/Zurich incl. DST). Tests:
`rules/4721-prod/tests/` (promtool unit tests and calendar cases at real
dates), run with `scripts/test-rules.py`.

### Mimir Ruler

G03, G04 and G08 run as Mimir ruler rules (enabled in
`helm/values/mimir-values.yaml`, container `mimir-ruler`, tenant
federation on). `rules/<tenant>/*.yaml` is loaded into namespace `repo`
of that tenant by `scripts/sync-mimir-rules.py` in `tenants:rollout`
(groups removed from the files are deleted, other namespaces are never
touched). There is no Mimir Alertmanager: ruler alerts show up in
Grafana's Alerting page as data-source-managed rules, without delivery.
`validate:rules` checks on every MR that `rules/` matches its sources
and passes promtool.

### Storage Showback (G06, FR-09)

The hourly `storage-usage` CronJob (`scripts/storage-usage.py`) lists
the four telemetry containers with a read/list-only SAS and pushes
`demo_storage_bytes{tenant, signal}` plus each tenant's showback budget
(`demo_storage_budget_bytes`, manifest size: S=5, M=50, L=125 GiB,
`SIZE_STORAGE_GB`). Pyroscope's not yet compacted multi-tenant segments
count as `unattributed`. Dashboard: *Operator: Storage Showback* (volume
per tenant and signal, % of budget, estimated monthly cost with an
adjustable CHF/GiB-month price). Showback only, nothing is enforced.

### Service Status (G08, FR-08)

Every tenant gets `rules/<tenant>/status.yaml`: `system:status:code`
0 functional, 1 degraded (slow SLO burn), 2 unknown (no telemetry for
10 minutes, or an SLO without SLI data), 3 disrupted (fast SLO burn). Business services and their
systems are defined in `services/business-services.yaml`; a federated
rule group in tenant `anonymous` computes `business_service:status:code`
as the worst member state (unknown ranks above degraded, a missing
member makes the service unknown). Dashboard: *Operator: Service Status*.

### Storage Tiering, Backup and Deletion (G10/G11, FR-17, NFR-14/15)

- **Tiering**: blobs in the four telemetry containers move to the Cool
  tier after 7 days without modification
  (`azurerm_storage_management_policy.observability`).
- **Protection**: blob versioning plus 7-day soft delete for blobs and
  containers; old versions are deleted after 7 days. No immutability
  policy on these containers - the compactors must delete blocks to
  enforce retention.
- **Restore** an accidentally deleted blob or container within 7 days:
  `az storage blob undelete` / `az storage container restore`, or
  promote an older version (`az storage blob copy start` from the
  version URL). Mimir/Loki/Tempo pick restored blocks up on their next
  bucket scan.
- **Deleting data of a tenant on request** (e.g. personal data in logs):
  Loki's delete API (`deletion_mode: filter-and-delete`):
  `POST /loki/api/v1/delete?query={...}&start=...&end=...` with
  `X-Scope-OrgID: <tenant>`; the compactor removes the lines after
  `retention_delete_delay` (2h). Traces, metrics and profiles have no
  selective delete in the OSS backends - they age out with the tenant's
  retention.
- **Legal hold**: not automated. A hold would copy the affected blocks
  into a separate container with an immutability policy - not on the
  live containers (see above).
- **Downsampling**: not available in Mimir OSS (no equivalent of Thanos
  downsampling); long-range queries read raw samples. Documented as a
  known limitation.

### Secrets (Key Vault) (G12, NFR-03)

The AKS add-on *Secrets Store CSI driver* with the Azure Key Vault
provider mounts secrets from the platform Key Vault
(`kv-otel-<suffix>`, access policies - the CI Service Principal may not
create role assignments) straight into pods, never into a Kubernetes
Secret. Mounted this way: Grafana's OpenClaw hook token and the
storage-usage SAS. Values are written write-only (`value_wo`): the hook
token (a CI/CD variable) is therefore not in the Terraform state at all.
The SAS still is - `azurerm_storage_account_sas` is a data source, whose
result Terraform always stores; it is read/list-only on the telemetry
blobs, rotated every 90 days, and the state itself is only readable
for project maintainers (GitLab-managed Terraform state). Still Kubernetes Secrets, and why: the
storage account key for Mimir/Loki/Tempo (passed by their Helm charts
into their own config Secrets) and Pyroscope (`pyroscope-storage`, env
expansion), OpenClaw's tokens (`openclaw-secrets`, environment
variables), the Pyroscope ingest credentials and the Postgres password -
each can move to a SecretProviderClass the same way when its consumer
supports file-based secrets.

### Budget Early Warning (G15, NFR-05)

`Tenant ingestion budget almost exhausted (>80% of daily budget)` in
`alerting/shared/operator-ingestion-budget.yaml`: per tenant and signal,
between 80 and 100% of the daily budget, before the enforcer throttles
at 100%. Visible in Grafana only (no mail in this demo).
