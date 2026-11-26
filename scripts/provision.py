#!/usr/bin/env python3
"""
Reconcile all onboarding manifests (manifests/{platforms,applications}/)
into this same repo: recompute per-tenant Mimir/Loki/Tempo/Pyroscope
ingestion limits, regenerate each system's dashboard, and give each
tenant its own Mimir/Loki/Tempo/Pyroscope Grafana datasources (without
these, every generated dashboard would query and display whichever one
tenant Grafana's static datasources happen to be pinned to, instead of
its own - a real bug found live once more than one tenant was actually
onboarded).

This fully regenerates the per-tenant override blocks in
mimir-tenant-overrides.yaml, loki-tenant-overrides.yaml,
tempo-tenant-overrides.yaml, and pyroscope-tenant-overrides.yaml from
the current set of manifests every run - not a partial merge - so it is
idempotent (same manifests in, same file content out) and there is
nothing left to hand-tune in those blocks afterwards; see the banner
comment this script writes above each block. Every onboarded tenant is
included, 4087 (the platform itself) as well - it goes through the same
onboarding/approval flow as everyone else, see README.md's IaC Roadmap.
All four systems' limits are derived from the exact same per-manifest
`size` tier (see `compute_overrides()`) - confirmed live
that Tempo/Pyroscope actually enforce these (real `429`/discard-metric
rejections observed against deliberately tiny test values before
writing this code). The `size` tier's DAILY ingestion budget
(helm/values/ingestion-daily-budgets.yaml, enforced by
scripts/ingestion-midnight-snapshot.py) is a separate quota per signal,
not one combined budget across every signal - see
SIZE_MIMIR_SAMPLES_PER_DAY's own comment for why (NFR-05 finding: a
single blended budget mixed genuinely different units and let one
signal's usage throttle another, unrelated signal).

Only writes the files in this checkout - does not commit, push, or
touch the actual cluster. The generated files are committed in the
merge request together with the manifest change (the onboarding/update/
offboarding MR scripts do it automatically, by hand: run this and
commit), and checked to be up to date by scripts/provisioning_sync.py
--check; tenants:rollout deploys them. See docs/self-service.md#onboarding-process.

Usage:
    python3 scripts/provision.py
"""
import io
import re
import subprocess
import sys
from pathlib import Path

import yaml as pyyaml
from ruamel.yaml import YAML
from ruamel.yaml.comments import CommentedMap
from ruamel.yaml.scalarstring import LiteralScalarString

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_SUBDIRS = ["platforms", "applications"]

# Duplicated from calculate-ingestion-budget.py (platform repo) rather
# than imported - cross-repo, and a hyphenated filename isn't a valid
# Python module name anyway. Keep in sync by hand if the formula changes.
RETENTION_DAYS = {"eng": 10, "at": 30, "prod": 30}
# GB/day per size tier - Loki/Tempo/Pyroscope's own daily ingestion
# budgets all use this same table directly (bytes = daily_gb * 1024**3).
SIZE_GB_PER_DAY = {"S": 1, "M": 10, "L": 25}
# G06 (FR-09): showback storage budget per size tier - GB of object
# storage (all four signals together, as stored, i.e. compressed) a
# tenant of that size is expected to occupy. Written as the "storage"
# key into ingestion-daily-budgets.yaml; scripts/storage-usage.py pushes
# it next to the measured volume. Showback only, nothing is enforced.
SIZE_STORAGE_GB = {"S": 5, "M": 50, "L": 125}
# NFR-05 audit finding: this used to be summed with Loki/Tempo/Pyroscope
# into one blended "daily_budget_bytes" per tenant, converting Mimir's
# sample count into a fake bytes-equivalent via a flat *1000 (~1KB/
# sample) guess so all four signals could be added together. That
# blended a real, measured unit (Loki/Tempo: uncompressed bytes;
# Pyroscope: bytes too, but COMPRESSED - a different, smaller basis
# than Loki/Tempo's) with a pure estimate (Mimir has no byte counter at
# all) into one number, and meant a tenant heavy on one signal could
# throttle its other, unrelated signals too. Each signal now gets its
# own independent daily budget (see compute_overrides()) and is
# enforced separately (ingestion-midnight-snapshot.py) - matching how
# e.g. Grafana Cloud's own quotas are also per-signal, never one
# blended number. Mimir's budget stays in ITS OWN native unit -
# samples/day - rather than pretending it's bytes: there is still no
# real byte counter to convert from, so a byte value would just be a
# renamed version of the same guess. Values below are that same
# *1000 estimate, kept only for continuity with today's live throttling
# behavior (SIZE_GB_PER_DAY[x] * 1024**3 / 1000) - now an explicit,
# dedicated table instead of a hidden runtime conversion, so it can be
# recalibrated independently of Loki/Tempo/Pyroscope's real byte
# budgets without touching their numbers at all.
SIZE_MIMIR_SAMPLES_PER_DAY = {"S": 1_073_742, "M": 10_737_418, "L": 26_843_546}

# Per-second rate/burst limit, deliberately generic - same for every
# tenant regardless of `size`, a technical platform-protection ceiling
# (don't let any single tenant overwhelm Mimir/Loki/Tempo/Pyroscope
# right now), not a business/cost concern. That's what
# SIZE_GB_PER_DAY/the ingestion-daily-budgets.yaml file below is for -
# a tenant's actual daily quota is enforced separately and actively by
# the ingestion-midnight-snapshot CronJob (throttles a tenant's own
# rate to near-zero once it crosses 100% of its own daily_gb budget,
# summed across all four signals - see that script's own comments),
# not by making small tenants chronically rate-limited the way the
# old size-derived rate/burst did (found live: it made
# legitimate S-tier application traffic get throttled for reasons
# unrelated to how much that tenant had actually used that day).
GENERIC_INGESTION_RATE_MB = 50
GENERIC_INGESTION_BURST_MB = 100
# Raised from 2/4 (this constant's original value, then briefly 10/20)
# - found live that even 10 MB/s wasn't enough for a
# single active demo tenant's REAL combined traffic: 4720 (OTel
# Astronomy Shop Demo) alone was measured rejecting ~3700-4500
# samples/s (Mimir) on top of ~300-2400/s accepted, once its own
# application metrics were combined with Tempo's metrics-generator
# continuously re-pushing that tenant's span-metrics series
# (traces_spanmetrics_calls_total/_bucket, the same series UC3's own
# alert and dashboard panels depend on) - the rejection was severe
# enough that metrics-generator's remote-write to Mimir fell over a
# hundred percent (zero successful pushes for over an hour, confirmed
# via prometheus_remote_storage_highest_timestamp_in_seconds staying
# frozen while prometheus_remote_storage_samples_failed_total climbed
# into the millions), silently breaking UC3's Request Rate/Latency
# panels and its shipping-latency alert entirely - not just a
# borderline case caught by chance while investigating an unrelated
# dashboard reading. 50/100 confirmed live to bring discards to zero
# for 4720 with headroom; still a demo-appropriate platform-protection
# ceiling, not a production capacity-planning exercise.

# Duplicated from generate-system-dashboard.py's own slugify() for the
# same reason as RETENTION_DAYS/SIZE_GB_PER_DAY above - keep in sync by
# hand if it ever changes.
def slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")

BANNER = (
    "Auto-generated by scripts/provision.py from manifests/ - do not "
    "hand-edit, changes here are overwritten on the next onboarding "
    "merge. Resize by editing the manifest instead."
)


def load_manifests():
    manifests = []
    for sub in MANIFEST_SUBDIRS:
        for path in sorted((REPO_ROOT / "manifests" / sub).glob("*.yaml")):
            manifests.append((path, pyyaml.safe_load(path.read_text())))
    return manifests


def compute_overrides(env: str, size: str):
    retention_days = RETENTION_DAYS[env]
    daily_gb = SIZE_GB_PER_DAY[size]
    retention_period = f"{retention_days * 24}h"
    rate_mb = GENERIC_INGESTION_RATE_MB
    burst_mb = GENERIC_INGESTION_BURST_MB

    mimir = {
        "ingestion_rate": int(rate_mb * 1000),
        "ingestion_burst_size": int(burst_mb * 1000),
        "compactor_blocks_retention_period": retention_period,
        # Off by default (0) - without it Mimir silently drops the
        # exemplars Tempo's metrics-generator already sends
        # (send_exemplars in tempo-values.yaml), so the Mimir
        # datasource's exemplar -> trace link (FR-04) had nothing to
        # link from.
        "max_global_exemplars_per_user": 100000,
    }
    loki = {
        "ingestion_rate_mb": rate_mb,
        "ingestion_burst_size_mb": burst_mb,
        "retention_period": retention_period,
    }
    tempo = {
        "ingestion": {
            "rate_strategy": "local",
            "rate_limit_bytes": int(rate_mb * 1024 * 1024),
            "burst_size_bytes": int(burst_mb * 1024 * 1024),
            "max_traces_per_user": 10000,
        },
        # Explicit, matching helm/values/tempo-values.yaml's own
        # overrides.defaults.metrics_generator block exactly - found
        # live that Tempo's per-tenant override struct
        # REPLACES the tenant's entire block wholesale rather than
        # merging field-by-field with the global default, so having
        # only "ingestion" here (as this override originally did)
        # silently zeroed out every tenant's metrics_generator
        # processors the moment ANY per-tenant ingestion override
        # existed - killing traces_spanmetrics_*/service-graph
        # generation platform-wide (confirmed live: removing one
        # tenant's override entirely made its active_series jump from
        # 0 to real numbers within the next collection cycle) without
        # any error, discard metric, or log line pointing at the cause.
        "metrics_generator": {
            "processors": ["service-graphs", "span-metrics"],
            "generate_native_histograms": "classic",
            "ingestion_time_range_slack": "0s",
            "native_histogram_bucket_factor": 1.1,
            "native_histogram_max_bucket_number": 100,
            "native_histogram_min_reset_duration": "15m0s",
        },
        # NFR-15: the tenant's own retention instead of Tempo's global
        # compactor default (48h).
        "compaction": {
            "block_retention": retention_period,
        },
    }
    pyroscope = {
        "ingestion_rate_mb": rate_mb,
        "ingestion_burst_size_mb": burst_mb,
        # NFR-15: Pyroscope v2's per-tenant retention (default 31d).
        "retention_period": retention_period,
    }
    # Daily budgets - one per signal, independent of the generic
    # rate/burst above (these are the numbers actually enforced, once
    # every 2 minutes, by the ingestion-midnight-snapshot CronJob
    # throttling a tenant's OWN signal once it crosses its OWN budget -
    # not the per-second limits above). Independent of each other too,
    # see SIZE_MIMIR_SAMPLES_PER_DAY's own comment for why this is no
    # longer one blended value across all four signals.
    daily_gb_bytes = daily_gb * 1024 * 1024 * 1024
    daily_budgets = {
        "loki": daily_gb_bytes,
        "tempo": daily_gb_bytes,
        "pyroscope": daily_gb_bytes,
        "mimir": SIZE_MIMIR_SAMPLES_PER_DAY[size],
    }
    return mimir, loki, tempo, pyroscope, daily_budgets


def collect_tenants(manifests):
    tenants = []
    for path, manifest in manifests:
        system_id = manifest["system_id"]
        for entry in manifest["environments"]:
            env, size = entry["env"], entry["size"]
            tenant_id = f"{system_id}-{env}"
            mimir_vals, loki_vals, tempo_vals, pyroscope_vals, daily_budgets = compute_overrides(env, size)
            tenants.append({
                "tenant_id": tenant_id,
                "manifest_file": path.name,
                "system_id": system_id,
                "name": manifest["name"],
                "env": env,
                "size": size,
                "mimir": mimir_vals,
                "loki": loki_vals,
                "tempo": tempo_vals,
                "daily_budgets": daily_budgets,
                "pyroscope": pyroscope_vals,
                "k8s_namespaces": list((manifest.get("k8s_namespaces") or {}).get(env, [])),
                "redaction_patterns": list((manifest.get("redaction") or {}).get("patterns", [])),
            })
    tenants.sort(key=lambda t: t["tenant_id"])
    return tenants


def rebuild_overrides(tenants, field, indent):
    """
    indent is the tenant keys' own indentation level (spaces). Passed
    explicitly and used to compute each comment's column - ruamel's
    yaml_add_eol_comment(), left to its own default column, reuses
    whatever column a neighboring entry's comment happens to have,
    which produces only 1 space before '#' for most entries (yamllint's
    "too few spaces before comment" warning) instead of the 2 it
    requires.
    """
    overrides = CommentedMap()
    for tenant in tenants:
        entry = CommentedMap(tenant[field])
        tenant_id = tenant["tenant_id"]
        overrides[tenant_id] = entry
        column = indent + len(tenant_id) + 1 + 2  # indent + "<id>:" + 2 spaces
        overrides.yaml_add_eol_comment(
            f"from {tenant['manifest_file']}, env {tenant['env']}, size {tenant['size']} (auto-provisioned)",
            tenant_id,
            column=column,
        )
    return overrides


def dump_deduped(yaml: YAML, data, path: Path, header: str = ""):
    """
    Dump via ruamel and write to path, collapsing consecutive duplicate
    BANNER comment lines into one. Re-running this script re-parses a
    file this function already wrote, and ruamel's own bookkeeping for
    "comment before a mapping's first key" does not consistently land in
    a place a second yaml_set_comment_before_after_key call can detect
    and overwrite - without this pass, the banner comment would grow by
    one duplicate line on every run rather than staying stable.

    header, if given, is prepended as-is (e.g. a top-of-file explanatory
    comment block) - needed for files this script fully regenerates from
    scratch each run (no read-modify-write of an existing file), since
    anything not written by this function is lost on the next run.
    """
    buf = io.StringIO()
    yaml.dump(data, buf)
    lines = buf.getvalue().split("\n")
    deduped = []
    for line in lines:
        if deduped and deduped[-1] == line and BANNER in line:
            continue
        deduped.append(line)
    content = "\n".join(deduped)
    if header:
        content = header + content
    path.write_text(content)


def update_mimir_values(tenants, yaml: YAML):
    """
    Writes helm/values/mimir-tenant-overrides.yaml - every onboarded
    tenant, 4087 (the platform itself) included, no special-casing (IaC
    Roadmap milestone, done - see mimir-values.yaml's own comment).
    Applied by deploy:tenants via
    `helm upgrade mimir --reuse-values -f mimir-tenant-overrides.yaml`,
    which deep-merges this file's runtimeConfig.overrides map on top of
    whatever deploy:observability-stack already deployed - verified live
    that Mimir hot-reloads the merged result with no pod restart.
    """
    path = REPO_ROOT / "helm" / "values" / "mimir-tenant-overrides.yaml"
    data = CommentedMap()
    data["runtimeConfig"] = CommentedMap()
    data["runtimeConfig"]["overrides"] = rebuild_overrides(tenants, "mimir", indent=4)
    data["runtimeConfig"].yaml_set_comment_before_after_key("overrides", before=BANNER, indent=2)
    header = (
        "---\n"
        "# Per-tenant Mimir ingestion budgets, every onboarded tenant\n"
        "# including 4087 (the platform itself - IaC Roadmap milestone,\n"
        "# done: no longer special-cased in mimir-values.yaml, goes\n"
        "# through onboarding like everyone else) - applied by\n"
        "# deploy:tenants via\n"
        "# `helm upgrade mimir --reuse-values -f mimir-tenant-overrides.yaml`,\n"
        "# which layers this file's runtimeConfig.overrides map on top of\n"
        "# whatever deploy:observability-stack already deployed (Helm deep-merges nested\n"
        "# maps under --reuse-values).\n\n"
    )
    dump_deduped(yaml, data, path, header=header)
    print(f"Updated {path}")


def update_loki_values(tenants, yaml: YAML):
    """
    Writes helm/values/loki-tenant-overrides.yaml - same as
    update_mimir_values() above, nested under `loki:` to match the base
    file's own path (--reuse-values merges by path).
    """
    path = REPO_ROOT / "helm" / "values" / "loki-tenant-overrides.yaml"
    data = CommentedMap()
    loki_section = CommentedMap()
    data["loki"] = loki_section
    loki_section["runtimeConfig"] = CommentedMap()
    loki_section["runtimeConfig"]["overrides"] = rebuild_overrides(tenants, "loki", indent=6)
    loki_section["runtimeConfig"].yaml_set_comment_before_after_key("overrides", before=BANNER, indent=4)
    header = (
        "---\n"
        "# Per-tenant Loki ingestion budgets, every onboarded tenant\n"
        "# including 4087 (the platform itself - IaC Roadmap milestone,\n"
        "# done: no longer special-cased in loki-values.yaml, goes\n"
        "# through onboarding like everyone else) - applied by\n"
        "# deploy:tenants via\n"
        "# `helm upgrade loki --reuse-values -f loki-tenant-overrides.yaml`,\n"
        "# which layers this file's loki.runtimeConfig.overrides map on top\n"
        "# of whatever deploy:observability-stack already deployed (Helm deep-merges\n"
        "# nested maps under --reuse-values). Nested under `loki:` to match the\n"
        "# base file's own path - --reuse-values merges by path, a bare\n"
        "# top-level `runtimeConfig:` here would land as an unrelated, ignored\n"
        "# key instead of merging into loki.runtimeConfig.overrides.\n"
    )
    dump_deduped(yaml, data, path, header=header)
    print(f"Updated {path}")


def update_tempo_values(tenants, yaml: YAML):
    """
    Writes helm/values/tempo-tenant-overrides.yaml - same pattern as
    update_mimir_values() above, bare top-level `per_tenant_overrides`
    key (no chart-name wrapper needed, matching how tempo-values.yaml's
    own base `overrides:` key is also un-nested) - confirmed live
    against the tempo-distributed chart's own values.yaml and this
    cluster's own running `/status/config`. The chart's own values.yaml
    warns "all values must be given for each per-tenant configuration
    block" - compute_overrides() always sets all four `ingestion.*`
    keys together for exactly this reason, never a partial override.
    """
    path = REPO_ROOT / "helm" / "values" / "tempo-tenant-overrides.yaml"
    data = CommentedMap()
    data["per_tenant_overrides"] = rebuild_overrides(tenants, "tempo", indent=2)
    data.yaml_set_comment_before_after_key("per_tenant_overrides", before=BANNER, indent=0)
    header = (
        "---\n"
        "# Per-tenant Tempo ingestion budgets, every onboarded tenant\n"
        "# including 4087, same convention as mimir-tenant-overrides.yaml -\n"
        "# applied by deploy:tenants via\n"
        "# `helm upgrade tempo grafana-community/tempo-distributed --reuse-values -f tempo-tenant-overrides.yaml`,\n"
        "# which layers this file's per_tenant_overrides map on top of\n"
        "# whatever deploy:observability-stack already deployed (Helm deep-merges\n"
        "# nested maps under --reuse-values). Confirmed live that\n"
        "# Tempo actually enforces these (real tempo_discarded_spans_total{reason=\n"
        '# \"rate_limited\"} increments against a deliberately tiny test value,\n'
        "# before this code was written) - Tempo had no per-tenant budget at\n"
        "# all before this file existed.\n"
    )
    dump_deduped(yaml, data, path, header=header)
    print(f"Updated {path}")


def update_pyroscope_values(tenants, yaml: YAML):
    """
    Writes helm/values/pyroscope-tenant-overrides.yaml - nested under
    `pyroscope:` to match the base chart's own values path (same reason
    loki-tenant-overrides.yaml nests under `loki:`) - confirmed live
    against the pyroscope chart's own values.yaml (`pyroscope.
    tenantOverrides`) and this cluster's own running
    `/api/v1/status/config`.
    """
    path = REPO_ROOT / "helm" / "values" / "pyroscope-tenant-overrides.yaml"
    data = CommentedMap()
    pyroscope_section = CommentedMap()
    data["pyroscope"] = pyroscope_section
    pyroscope_section["tenantOverrides"] = rebuild_overrides(tenants, "pyroscope", indent=4)
    pyroscope_section.yaml_set_comment_before_after_key("tenantOverrides", before=BANNER, indent=2)
    header = (
        "---\n"
        "# Per-tenant Pyroscope ingestion budgets, every onboarded tenant\n"
        "# including 4087, same convention as loki-tenant-overrides.yaml -\n"
        "# applied by deploy:tenants via\n"
        "# `helm upgrade pyroscope grafana/pyroscope --reuse-values -f pyroscope-tenant-overrides.yaml`,\n"
        "# which layers this file's pyroscope.tenantOverrides map on top of\n"
        "# whatever deploy:observability-stack already deployed (Helm deep-merges\n"
        "# nested maps under --reuse-values). Confirmed live that\n"
        "# Pyroscope actually enforces these (real HTTP 429 resource_exhausted\n"
        "# rejections against a deliberately tiny test value, before this code\n"
        "# was written) - pyroscope-values.yaml's own header comment previously\n"
        '# said this was "deliberately not configured"; that\'s no longer true,\n'
        "# see this file instead.\n"
    )
    dump_deduped(yaml, data, path, header=header)
    print(f"Updated {path}")


def update_ingestion_budgets(tenants, yaml: YAML):
    """
    Writes helm/values/ingestion-daily-budgets.yaml - a
    tenant -> {signal: daily_budget} map, one nested block per onboarded
    tenant, one entry per signal (Loki/Tempo/Pyroscope in bytes, Mimir
    in samples - see SIZE_MIMIR_SAMPLES_PER_DAY's own comment for why
    Mimir doesn't get a fake bytes value). NFR-05: was a single flat
    tenant -> bytes scalar per tenant (one blended budget across all
    four signals) until found not to be best practice - see
    SIZE_MIMIR_SAMPLES_PER_DAY's comment for the full reasoning. Not a
    Helm chart values file (no chart consumes this) - mounted directly
    into the ingestion-midnight-snapshot CronJob (terraform/
    environments/observability-stack/main.tf) as a plain data file, so
    the enforcement script running there knows each tenant's actual
    daily quota per signal without needing git/manifest access at
    runtime. Changes only on onboarding/resize (daily_gb is a
    manifest-level `size` property), not daily - contrast with the
    per-tenant runtime ConfigMaps the same CronJob also reads/writes
    live, which change throughout the day as tenants get
    throttled/un-throttled.
    """
    path = REPO_ROOT / "helm" / "values" / "ingestion-daily-budgets.yaml"
    data = CommentedMap()
    # Reserved keys (never a valid tenant_id shape) carrying the same
    # generic rate/burst compute_overrides() gives every tenant - added
    # here, not hardcoded a second time in ingestion-midnight-snapshot.py,
    # after found live that a hand-duplicated copy of these two numbers
    # in that script went stale (still 2/4 MB) across two separate
    # bumps of this constant, silently reverting a tenant back to a
    # far-too-low limit every time the enforcer restored it at a
    # midnight rollover. One source of truth now - the enforcer reads
    # these two lines the same way it reads every tenant's budget.
    data["__generic_rate_mb__"] = GENERIC_INGESTION_RATE_MB
    data["__generic_burst_mb__"] = GENERIC_INGESTION_BURST_MB
    for tenant in tenants:
        tenant_id = tenant["tenant_id"]
        data[tenant_id] = CommentedMap(tenant["daily_budgets"])
        data[tenant_id]["storage"] = SIZE_STORAGE_GB[tenant["size"]] * 1024**3
        # tenant key opens a nested block (like rebuild_overrides()'s
        # tenant keys) - nothing else on that line, so the comment
        # column is just "<id>:" + 2 spaces, no value length to skip.
        column = len(tenant_id) + 1 + 2
        data.yaml_add_eol_comment(
            f"from {tenant['manifest_file']}, env {tenant['env']}, size {tenant['size']} (auto-provisioned)",
            tenant_id,
            column=column,
        )
    data.yaml_set_start_comment(BANNER)
    header = (
        "---\n"
        "# Per-tenant, per-signal daily ingestion budget, every onboarded\n"
        "# tenant including 4087 - see scripts/provision.py's\n"
        "# compute_overrides() for the derivation (size tier only,\n"
        "# independent of the generic per-second rate/burst limit every\n"
        "# tenant shares - see that function's own comment for why the\n"
        "# two are deliberately decoupled). Loki/Tempo/Pyroscope budgets\n"
        "# are in bytes; Mimir's is in samples (its own native unit - see\n"
        "# SIZE_MIMIR_SAMPLES_PER_DAY's comment for why there is no\n"
        "# Mimir bytes value here). Each signal is enforced independently\n"
        "# - NFR-05 finding: previously one blended byte budget summed\n"
        "# across all four signals, which meant a tenant heavy on one\n"
        "# signal could throttle its other, unrelated signals too, and\n"
        "# blended together genuinely different bases (Loki/Tempo real\n"
        "# uncompressed bytes, Pyroscope real but COMPRESSED bytes,\n"
        "# Mimir a pure sample-count estimate) as if they were one unit.\n"
        "# Read by the ingestion-midnight-snapshot CronJob (mounted as a\n"
        "# plain file, not a Helm values file - no chart consumes this)\n"
        "# to know when a tenant has crossed 100% of a given signal's own\n"
        "# daily quota and should be throttled on that signal alone. The\n"
        "# two __generic_..._mb__ keys (never a valid tenant_id shape)\n"
        "# carry the same generic rate/burst every tenant's own\n"
        "# runtime-config override uses - the enforcer reads them from\n"
        "# here too, rather than a second, hand-maintained copy of the\n"
        "# same two numbers. The per-tenant \"storage\" key is not a daily\n"
        "# ingestion budget: it is the showback storage budget in bytes\n"
        "# (G06, SIZE_STORAGE_GB), read by the storage-usage CronJob; the\n"
        "# enforcer only looks at the four signal keys.\n\n"
    )
    dump_deduped(yaml, data, path, header=header)
    print(f"Updated {path}")


# Cross-signal links between one tenant's own four datasources
# (FR-01/FR-04/FR-15) - always within the same tenant, never across.
# "$$" is Grafana provisioning's escape for a literal "$": provisioning
# files expand $VAR/${VAR} from the environment, which would otherwise
# swallow Grafana's own ${__trace.traceId}-style link variables.
# Label names verified live: Loki stream label service_name plus
# structured metadata trace_id (OTLP logs), span-metrics label service,
# Tempo exemplar label traceID.
def _tempo_correlation(tenant_id: str) -> dict:
    return {
        "tracesToLogsV2": {
            "datasourceUid": f"loki-{tenant_id}",
            "spanStartTimeShift": "-5m",
            "spanEndTimeShift": "5m",
            "tags": [{"key": "service.name", "value": "service_name"}],
            "customQuery": True,
            "query": '{$${__tags}} | trace_id="$${__trace.traceId}"',
        },
        "tracesToMetrics": {
            "datasourceUid": f"mimir-{tenant_id}",
            "spanStartTimeShift": "-5m",
            "spanEndTimeShift": "5m",
            "tags": [{"key": "service.name", "value": "service"}],
            "queries": [
                {"name": "Request rate", "query": "sum(rate(traces_spanmetrics_calls_total{$$__tags}[5m]))"},
                {"name": "Error rate", "query": 'sum(rate(traces_spanmetrics_calls_total{$$__tags, status_code="STATUS_CODE_ERROR"}[5m]))'},
                {"name": "p95 latency", "query": "histogram_quantile(0.95, sum by (le) (rate(traces_spanmetrics_latency_bucket{$$__tags}[5m])))"},
            ],
        },
        "tracesToProfiles": {
            "datasourceUid": f"pyroscope-{tenant_id}",
            "tags": [{"key": "service.name", "value": "service_name"}],
            "profileTypeId": "process_cpu:cpu:nanoseconds:cpu:nanoseconds",
        },
        "serviceMap": {"datasourceUid": f"mimir-{tenant_id}"},
        "nodeGraph": {"enabled": True},
        "lokiSearch": {"datasourceUid": f"loki-{tenant_id}"},
    }


def _loki_correlation(tenant_id: str) -> dict:
    return {
        "derivedFields": [{
            "name": "TraceID",
            "matcherType": "label",
            "matcherRegex": "trace_id",
            "url": "$${__value.raw}",
            "urlDisplayLabel": "View trace",
            "datasourceUid": f"tempo-{tenant_id}",
        }],
    }


def _mimir_correlation(tenant_id: str) -> dict:
    return {
        "exemplarTraceIdDestinations": [
            {"name": "traceID", "datasourceUid": f"tempo-{tenant_id}"},
            {"name": "trace_id", "datasourceUid": f"tempo-{tenant_id}"},
        ],
    }


def _render_datasource_configmap(tenant_id: str, yaml: YAML) -> str:
    # uid is explicit and deterministic (<mimir|loki|tempo>-<tenant_id>,
    # e.g. "mimir-4711-prod") - without it Grafana auto-generates one
    # non-deterministically at provisioning time, which alerting/'s
    # independently-authored alert-rule YAML (datasourceUid field)
    # couldn't reliably reference. See alerting/README.md.
    # manageAlerts defaults to true for prometheus/loki-type datasources -
    # makes Grafana's Alerting page also try to fetch "data source-managed
    # rules" from that datasource's own ruler API. Both this repo's Mimir
    # and Loki have their ruler scaled to 0 (mimir-values.yaml/
    # loki-values.yaml, "not needed for demo" - Grafana's own engine
    # evaluates alert rules, not the ruler), so that fetch always fails
    # ("Errors loading rules from ..."). False here matches the same fix
    # applied to the static Mimir-anonymous datasource in
    # grafana-values.yaml. Tempo/Pyroscope don't have this capability at
    # all, so they don't need the field.
    entries = []
    for ds_name, ds_type, ds_uid_prefix, url, extra_json_data in [
        (f"Mimir-{tenant_id}", "prometheus", "mimir", "http://mimir-gateway.observability.svc:80/prometheus", {"manageAlerts": False, **_mimir_correlation(tenant_id)}),
        (f"Loki-{tenant_id}", "loki", "loki", "http://loki-gateway.observability.svc:80/", {"manageAlerts": False, **_loki_correlation(tenant_id)}),
        (f"Tempo-{tenant_id}", "tempo", "tempo", "http://tempo-query-frontend.observability.svc:3200", _tempo_correlation(tenant_id)),
        (f"Pyroscope-{tenant_id}", "grafana-pyroscope-datasource", "pyroscope", "http://pyroscope-query-frontend.observability.svc:4040", {}),
    ]:
        entries.append({
            "name": ds_name,
            "type": ds_type,
            "uid": f"{ds_uid_prefix}-{tenant_id}",
            "url": url,
            "access": "proxy",
            "jsonData": {"httpHeaderName1": "X-Scope-OrgID", **extra_json_data},
            "secureJsonData": {"httpHeaderValue1": tenant_id},
        })

    inner_buf = io.StringIO()
    yaml.dump({"apiVersion": 1, "datasources": entries}, inner_buf)

    configmap = {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {
            "name": f"grafana-datasource-{tenant_id}",
            "namespace": "observability",
            "labels": {"grafana_datasource": "1"},
        },
        "data": {f"{tenant_id}.yaml": LiteralScalarString(inner_buf.getvalue())},
    }
    outer_buf = io.StringIO()
    yaml.dump(configmap, outer_buf)
    return f"---\n# {BANNER}\n" + outer_buf.getvalue()


def _render_tombstone_configmap(tenant_id: str, yaml: YAML) -> str:
    """
    Grafana's file-based datasource provisioning is add/update-only - it
    does NOT delete a previously-provisioned datasource just because its
    source file disappears (unlike dashboard provisioning, which does
    track deletions). Confirmed live: removing a tenant's ConfigMap, even
    across a full Grafana pod restart, left its three datasources
    sitting in Grafana's DB - and DELETE /api/datasources rejects them
    outright ("Cannot delete read-only data source") since they're
    provisioning-owned. The only way to actually remove them is an
    explicit `deleteDatasources` entry in a provisioning file, which
    Grafana processes on the next provisioning reload.

    So an offboarded tenant's ConfigMap is never actually removed
    from datasources/ - it's rewritten in place, permanently,
    to a `deleteDatasources` tombstone instead (same filename, so
    `kubectl apply -f datasources/` keeps reapplying it every
    run - harmless once the datasources are actually gone, `deleteDatasources`
    is a no-op for names that don't exist).
    """
    entries = [
        {"name": f"Mimir-{tenant_id}", "orgId": 1},
        {"name": f"Loki-{tenant_id}", "orgId": 1},
        {"name": f"Tempo-{tenant_id}", "orgId": 1},
        {"name": f"Pyroscope-{tenant_id}", "orgId": 1},
    ]

    inner_buf = io.StringIO()
    yaml.dump({"apiVersion": 1, "deleteDatasources": entries}, inner_buf)

    configmap = {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {
            "name": f"grafana-datasource-{tenant_id}",
            "namespace": "observability",
            "labels": {"grafana_datasource": "1"},
        },
        "data": {f"{tenant_id}.yaml": LiteralScalarString(inner_buf.getvalue())},
    }
    outer_buf = io.StringIO()
    yaml.dump(configmap, outer_buf)
    return (
        "---\n"
        f"# {BANNER}\n"
        f"# {tenant_id} is no longer onboarded - this ConfigMap is a permanent\n"
        "# tombstone (deleteDatasources), not a stale leftover. See\n"
        "# _render_tombstone_configmap() in provision.py for why it can't\n"
        "# just be removed.\n" + outer_buf.getvalue()
    )


def update_grafana_datasources(tenants, yaml: YAML):
    """
    Gives every onboarded tenant its own Mimir/Loki/Tempo/Pyroscope
    datasource quartet, pinned to that tenant via the X-Scope-OrgID header -
    without this, every onboarded system's dashboard would query and
    display whichever one tenant the datasources happen to be pinned to
    (found live: 8 of 9 non-4087 dashboards showing 4087-prod's data).
    4087 (the platform itself) is included like everyone else (IaC
    Roadmap milestone, done) - it used to be excluded, with a static
    triplet hand-authored in grafana-values.yaml instead; see that
    file's own comment.

    One ConfigMap per tenant, written to datasources/ and
    auto-discovered by Grafana's datasources sidecar (see
    grafana-values.yaml's sidecar.datasources) - applied by the
    deploy:tenants CI job, not deploy:observability-stack, mirroring how dashboards
    already split between shared/ and per-tenant. Filenames are
    <system_id>-<slug-of-name>-<env>.yaml, matching the <id>-<name>
    convention instrumentation/applications/ and dashboards/<env>/ both
    use - the slug is cosmetic only (matched back to a tenant_id via
    each file's own metadata.name, "grafana-datasource-<tenant_id>",
    never by parsing the filename), since manifests/schema.json makes
    name immutable once onboarded (see the self-service form's own
    "Type/name can't be changed here" hint) - a tenant's filename never
    needs to change mid-lifetime. Fully regenerated from scratch each
    run - an offboarded tenant's file is rewritten to a
    deleteDatasources tombstone in place (same filename, so it keeps
    whatever name it last had) rather than removed, see
    _render_tombstone_configmap(). A stale duplicate under the old
    filename is only possible if a system_id is offboarded and later
    re-onboarded under a different name - handled below by deleting it
    before writing the freshly-named file.
    """
    out_dir = REPO_ROOT / "datasources"
    out_dir.mkdir(parents=True, exist_ok=True)

    current_ids = {t["tenant_id"] for t in tenants}
    filenames_by_id = {
        t["tenant_id"]: f"{t['system_id']}-{slugify(t['name'])}-{t['env']}.yaml"
        for t in tenants
    }

    tombstoned = 0
    for existing in list(out_dir.glob("*.yaml")):
        existing_content = yaml.load(existing.read_text())
        existing_tenant_id = existing_content["metadata"]["name"].removeprefix("grafana-datasource-")
        if existing_tenant_id in current_ids:
            if existing.name != filenames_by_id[existing_tenant_id]:
                existing.unlink()
        else:
            existing.write_text(_render_tombstone_configmap(existing_tenant_id, yaml))
            tombstoned += 1

    for tenant_id in sorted(current_ids):
        (out_dir / filenames_by_id[tenant_id]).write_text(_render_datasource_configmap(tenant_id, yaml))

    print(
        f"Updated {out_dir} ({len(current_ids)} per-tenant datasource ConfigMaps, "
        f"{tombstoned} offboarded-tenant tombstones)"
    )


def update_gateway_tenant_allowlist(tenants, yaml: YAML):
    """
    Keeps the gateway's filter/reject_unknown_tenants processor (see
    otel-gateway-collector.yaml) in sync with the current set of
    onboarded tenants - real multi-tenancy enforcement, not just
    cosmetic: without this allowlist, the gateway's headers_setter
    extension forwards whatever tenant_id a client sets unvalidated,
    and Mimir/Loki create a tenant implicitly on first write (no
    pre-registration needed), so an instrumented-but-not-yet-onboarded
    system's telemetry would otherwise be silently accepted under the
    global default limits - invisible (no dashboard), but not actually
    rejected. "anonymous" (self-monitoring) is always allowed in
    addition to the real tenant IDs below.

    Pyroscope tenants aren't gated by this allowlist - continuous
    profiling deliberately bypasses the gateway entirely (see B12 in
    the main README), so there's no OTLP traffic here for it to
    filter. Pyroscope trusts whatever X-Scope-OrgID its own clients
    set directly, same trust model as every other signal, just
    enforced one layer earlier.
    """
    path = REPO_ROOT / "collector-gateway" / "otel-gateway-collector.yaml"
    data = yaml.load(path.read_text())
    processors = data["spec"]["config"]["processors"]

    allowed = sorted({"anonymous"} | {t["tenant_id"] for t in tenants})
    # No re.escape() here on purpose: OTTL's string-literal grammar
    # rejects backslash escapes it doesn't recognize (found live -
    # re.escape()'s `\-` crashed the gateway collector with "invalid
    # quoted string", taking it down until fixed). Every real tenant_id
    # is "<digits>-<lowercase>" (system_id from the manifest, env from a
    # fixed enum) - nothing in that charset is regex-special, so no
    # escaping is actually needed; assert it stays that way instead of
    # silently trusting it.
    for tenant_id in allowed:
        assert re.fullmatch(r"[a-z0-9-]+", tenant_id), (
            f"tenant_id {tenant_id!r} has unexpected characters - would need safe "
            "escaping for the gateway's OTTL allowlist condition, see this comment"
        )
    # Per-signal attribute, not resource.attributes - the gateway's
    # attributes/tag_tenant processor (attributesprocessor) writes to
    # each span/log_record/datapoint's own attribute map, never to
    # resource-level attributes (confirmed against that processor's own
    # README after a live outage caused by assuming otherwise: every
    # item hit the resource.attributes["tenant_id"] == nil branch and
    # got dropped, 100% of traffic, twice).
    condition = (
        'attributes["tenant_id"] == nil or not IsMatch(attributes["tenant_id"], '
        f'"^({"|".join(allowed)})$")'
    )

    reject_unknown_tenants = processors["filter/reject_unknown_tenants"]
    reject_unknown_tenants["traces"]["span"][0] = condition
    reject_unknown_tenants["metrics"]["datapoint"][0] = condition
    reject_unknown_tenants["logs"]["log_record"][0] = condition

    # header="---\n" - found live: this is the only generated file that's
    # read-modify-written (not built from scratch each run like the
    # others), and ruamel doesn't re-emit a document's original "---"
    # marker on round-trip unless explicit_start is set on the YAML()
    # instance - which isn't done globally here, since that would double
    # up the "---" this function's own header already adds on the
    # from-scratch generators (mimir/loki tenant-overrides, per-tenant
    # datasource ConfigMaps). Without this, a hand-added "---" on this
    # one file would silently disappear again on the very next run.
    dump_deduped(yaml, data, path, header="---\n")
    print(f"Updated {path} ({len(allowed)} allowed tenant_id values, including anonymous)")


def update_tenant_client_certs(tenants, yaml: YAML):
    """
    NFR-04 mTLS rollout, Phase 2 (README "Open Points") - per onboarded
    tenant, a 3-resource chain rooted at the shared internal-ca
    ClusterIssuer (terraform/environments/observability-stack-crs/
    main.tf):
      1. intermediate-cas/<id>.yaml: a CA Certificate (isCA: true),
         issued BY internal-ca - this tenant's own intermediate CA.
      2. issuers/<id>.yaml: a namespaced Issuer (not ClusterIssuer)
         whose spec.ca.secretName is that intermediate's own Secret.
      3. clients/<id>.yaml: the actual OTLP client leaf Certificate,
         issued via THAT tenant's own Issuer from (2) - never directly
         from the shared internal-ca.

    Found live testing Phase 3: a first version of this issued every
    tenant's leaf cert directly from the one shared internal-ca, which
    meant every tenant's Secret held the SAME ca.crt (internal-ca's own
    cert) - client_ca_file on ANY tenant's receiver then accepted ANY
    OTHER tenant's cert too, since "signed by a trusted CA" was true
    for all of them identically. Confirmed live with a Python TLS probe
    (tenant 1229's cert accepted on tenant 1286's own dedicated
    receiver).

    This intermediate-CA chain alone does NOT fix that - found live
    again, the SAME cross-tenant acceptance still happened after adding
    it. Root cause: cert-manager's ca-issuer propagates ca.crt from
    whatever Secret an Issuer's spec.ca.secretName points at. Each
    tenant's own intermediate-cas/<id>.yaml Secret has its OWN ca.crt
    set to the shared internal-ca root (since the root issued it), so
    the leaf Secret's ca.crt inherits that same shared root too - not
    this tenant's intermediate. The actual fix (in
    update_gateway_tenant_mtls_receivers()) is pinning each receiver's
    client_ca_file to the tenant's intermediate Secret's tls.crt
    directly, not to any Secret's ca.crt field - exactly the "per-tenant
    intermediate CA (not a single shared CA)" design this repo's own
    README already called for before this rollout started.

    Same fileset()+yamldecode convention as local.datasources/
    local.dashboards, just three parallel subdirectories instead of
    one flat one - see terraform/environments/tenants/main.tf's own
    local.tenant_intermediate_cas/local.tenant_issuers/
    local.tenant_client_certs.

    No tombstones needed on offboarding (unlike
    _render_tombstone_configmap() for Grafana's own add/update-only
    datasource provisioning) - cert-manager's CRD deletion is a real,
    correct removal, so an orphaned file is simply deleted, same as
    cleanup_orphaned_dashboards() below does for dashboards.
    """
    base_dir = REPO_ROOT / "tls-certs"
    intermediate_dir = base_dir / "intermediate-cas"
    issuer_dir = base_dir / "issuers"
    client_dir = base_dir / "clients"
    for d in (intermediate_dir, issuer_dir, client_dir):
        d.mkdir(parents=True, exist_ok=True)

    current_ids = {t["tenant_id"] for t in tenants}

    def write(path: Path, manifest: dict):
        buf = io.StringIO()
        yaml.dump(manifest, buf)
        path.write_text(f"---\n# {BANNER}\n" + buf.getvalue())

    for tenant_id in sorted(current_ids):
        write(intermediate_dir / f"{tenant_id}.yaml", {
            "apiVersion": "cert-manager.io/v1",
            "kind": "Certificate",
            "metadata": {
                "name": f"otlp-intermediate-ca-{tenant_id}",
                "namespace": "observability",
            },
            "spec": {
                "isCA": True,
                "secretName": f"otlp-intermediate-ca-cert-{tenant_id}",
                "issuerRef": {"name": "internal-ca", "kind": "ClusterIssuer"},
                "commonName": f"{tenant_id} OTLP Intermediate CA",
                "usages": ["cert sign", "crl sign", "digital signature", "key encipherment"],
                "duration": "8760h",
                "renewBefore": "720h",
                # Keep the key on renewal (cert-manager >= 1.18 rotates it
                # by default): the gateway hot-reloads this CA
                # (client_ca_file_reload), and a new key would instantly
                # invalidate every VM client certificate it signed. Key
                # rotation is a deliberate manual step - see README
                # "mTLS certificate lifecycle".
                "privateKey": {"rotationPolicy": "Never"},
            },
        })
        write(issuer_dir / f"{tenant_id}.yaml", {
            "apiVersion": "cert-manager.io/v1",
            "kind": "Issuer",
            "metadata": {
                "name": f"otlp-issuer-{tenant_id}",
                "namespace": "observability",
            },
            "spec": {
                "ca": {"secretName": f"otlp-intermediate-ca-cert-{tenant_id}"},
            },
        })
        write(client_dir / f"{tenant_id}.yaml", {
            "apiVersion": "cert-manager.io/v1",
            "kind": "Certificate",
            "metadata": {
                "name": f"otlp-client-{tenant_id}",
                "namespace": "observability",
            },
            "spec": {
                "secretName": f"otlp-client-cert-{tenant_id}",
                "issuerRef": {"name": f"otlp-issuer-{tenant_id}", "kind": "Issuer"},
                "commonName": tenant_id,
                "usages": ["client auth"],
                "duration": "2160h",
                "renewBefore": "360h",
            },
        })

    removed = 0
    for d in (intermediate_dir, issuer_dir, client_dir):
        for path in sorted(d.glob("*.yaml")):
            if path.stem not in current_ids:
                path.unlink()
                removed += 1
                print(f"Removed orphaned manifest {path.relative_to(REPO_ROOT)}")

    print(f"Updated {base_dir} ({len(current_ids)} per-tenant intermediate CA / Issuer / client cert chains, {removed} removed)")


# F13: per-tenant mTLS receiver port. Environment offset + 4-digit
# system_id (manifests/schema.json enforces 1000-9999), so every tenant_id
# gets its own port - previously all environments of one system_id shared
# 20000+system_id. prod keeps its old port. Mirrored in
# terraform/environments/tenants/main.tf (local.tenant_otlp_grpc_ports).
TENANT_GRPC_PORT_BASE = {"prod": 20000, "at": 30000, "eng": 40000}


def tenant_grpc_port(system_id, env: str) -> int:
    return TENANT_GRPC_PORT_BASE[env] + int(system_id)


def update_gateway_tenant_mtls_receivers(tenants, yaml: YAML):
    """
    NFR-04 mTLS rollout, Phase 3 (README "Open Points") - one dedicated
    otlp/tenant-<id> receiver per onboarded tenant, each its own port,
    each trusting only that tenant's own CA-signed client cert
    (client_ca_file, from update_tenant_client_certs()'s Secret) -
    tenant_id is then set by a hardcoded attributes processor in that
    tenant's own pipeline branch, never read from client-supplied
    metadata the way the shared otlp receiver's headers_setter/
    attributes/tag_tenant/filter/reject_unknown_tenants chain still
    does. That shared receiver is untouched here and keeps running -
    this is additive (new receivers/pipelines alongside the old one),
    not a cutover; see README B-section for the migration story.

    The export side needed the same treatment - found live: the shared
    otlp/tempo, otlphttp/loki, prometheusremotewrite exporters'
    headers_setter auth reads X-Scope-OrgID from client gRPC/HTTP
    context, which these mTLS receivers never populate, so every
    tenant's data was silently landing under headers_setter's own
    "anonymous" default_value instead of the real tenant. Per-tenant
    exporters below set a static X-Scope-OrgID header instead, needing
    no context at all.

    Ports are derived from each tenant's own system_id and env
    (tenant_grpc_port()), not sorted position - onboarding an unrelated
    new tenant must never reassign an existing tenant's port. gRPC only:
    Traefik's IngressRouteTCP routes the VM collectors' gRPC (14317) to
    these ports; an mTLS HTTP receiver per tenant had no client and was
    dropped with F13.

    The server certificate (shared across every tenant receiver - only
    the CLIENT ca_file differs per tenant) comes from a separate,
    non-per-tenant Certificate (otel-gateway-server, terraform/
    environments/observability-stack-crs/main.tf).
    """
    path = REPO_ROOT / "collector-gateway" / "otel-gateway-collector.yaml"
    data = yaml.load(path.read_text())
    spec = data["spec"]
    config = spec["config"]
    receivers = config["receivers"]
    processors = config["processors"]
    exporters = config["exporters"]
    pipelines = config["service"]["pipelines"]

    current = {t["tenant_id"]: t for t in tenants}

    server_volume = "otel-gateway-server-tls"
    server_mount = "/etc/otel-gateway-tls/server"

    def tenant_volume(tenant_id: str) -> str:
        return f"tenant-ca-{tenant_id}"

    def tenant_mount(tenant_id: str) -> str:
        return f"/etc/otel-gateway-tls/{tenant_volume(tenant_id)}"

    # --- volumes/volumeMounts: server cert (static) + one CA per tenant ---
    spec.setdefault("volumes", [])
    spec.setdefault("volumeMounts", [])
    valid_volume_names = {server_volume} | {tenant_volume(tid) for tid in current}
    spec["volumes"] = [v for v in spec["volumes"] if v["name"] in valid_volume_names]
    spec["volumeMounts"] = [m for m in spec["volumeMounts"] if m["name"] in valid_volume_names]

    def upsert_volume(name: str, secret_name: str, mount_path: str):
        for v in spec["volumes"]:
            if v["name"] == name:
                v["secret"]["secretName"] = secret_name
                break
        else:
            spec["volumes"].append({"name": name, "secret": {"secretName": secret_name}})
        for m in spec["volumeMounts"]:
            if m["name"] == name:
                m["mountPath"] = mount_path
                break
        else:
            spec["volumeMounts"].append({"name": name, "mountPath": mount_path, "readOnly": True})

    upsert_volume(server_volume, "otel-gateway-server-cert", server_mount)
    for tenant_id in current:
        # Mounts the tenant's own INTERMEDIATE CA Secret, not its client
        # leaf Secret. Found live: cert-manager's ca-issuer propagates
        # ca.crt from whatever secret an Issuer's spec.ca.secretName
        # points at - since that intermediate Secret's own ca.crt is
        # itself the shared internal-ca root (it was issued BY that
        # root), the leaf Secret's ca.crt ends up being the shared root
        # too, not this tenant's intermediate. Pinning client_ca_file to
        # the intermediate's own tls.crt (below) is what actually scopes
        # trust to just this tenant - confirmed live with a cross-tenant
        # TLS probe after the first (root-propagated) version still
        # accepted every tenant's cert on every other tenant's receiver.
        upsert_volume(tenant_volume(tenant_id), f"otlp-intermediate-ca-cert-{tenant_id}", tenant_mount(tenant_id))

    # Server volume first, tenants sorted - so the output only depends on
    # the manifests, not on the order tenants were onboarded in (found
    # live: a re-onboarded tenant's volume was appended at the end).
    def volume_order(entry):
        return (entry["name"] != server_volume, entry["name"])

    spec["volumes"].sort(key=volume_order)
    spec["volumeMounts"].sort(key=volume_order)

    # --- ports: static ones untouched, one gRPC port per tenant.
    # Named "p<port>", not "tenant-<id>-grpc"/"-http" - Kubernetes
    # Service port names are capped at 15 chars (IANA_SVC_NAME), and a
    # tenant_id like "1286-prod" already blows past that; not
    # referenced by name anywhere downstream, so short and unique is
    # all that's needed. Same convention terraform/environments/
    # tenants/main.tf's own otel_gateway_tenant_mtls Service uses. ---
    static_ports = [p for p in spec["ports"] if not re.fullmatch(r"p\d+", p["name"])]
    tenant_ports = []
    port_owner = {}
    for tenant_id, t in sorted(current.items()):
        port = tenant_grpc_port(t["system_id"], t["env"])
        assert port not in port_owner, f"port {port} of {tenant_id} already used by {port_owner[port]}"
        port_owner[port] = tenant_id
        tenant_ports.append({"name": f"p{port}", "port": port})
    spec["ports"] = static_ports + tenant_ports

    # --- receivers: drop stale tenant ones, (re)build current ones ---
    for key in [k for k in list(receivers) if k.startswith("otlp/tenant-")]:
        del receivers[key]
    for tenant_id, t in sorted(current.items()):
        port = tenant_grpc_port(t["system_id"], t["env"])
        tls_block = {
            "cert_file": f"{server_mount}/tls.crt",
            "key_file": f"{server_mount}/tls.key",
            # tls.crt, not ca.crt: this Secret IS the tenant's own
            # intermediate CA cert (see upsert_volume above) - that's the
            # trust anchor we want, not its own ca.crt (the shared root).
            "client_ca_file": f"{tenant_mount(tenant_id)}/tls.crt",
            # F11: cert-manager renews the server cert and the tenant
            # intermediate in place (mounted Secrets update without a pod
            # restart) - re-read them periodically, otherwise the Gateway
            # keeps serving the old, eventually expired server cert.
            # reload_interval covers cert_file/key_file only; the tenant
            # CA needs client_ca_file_reload.
            "reload_interval": "1h",
            "client_ca_file_reload": True,
        }
        receivers[f"otlp/tenant-{tenant_id}"] = {
            "protocols": {
                "grpc": {
                    "endpoint": f"0.0.0.0:{port}",
                    "tls": tls_block,
                    "include_metadata": True,
                    # Allow the clients' gRPC keepalive pings (instrumentation/
                    # platforms/*/config.yaml, otlp/host keepalive.time 30s).
                    # gRPC's default enforcement (min 5m, only with active
                    # streams) would answer them with GOAWAY too_many_pings.
                    # Found live: after an AKS node reimage, a VM's
                    # connection via the Azure LB died silently and,
                    # without keepalive, its metrics hit DeadlineExceeded
                    # until the collector was restarted.
                    "keepalive": {"enforcement_policy": {"min_time": "10s", "permit_without_stream": True}},
                },
            }
        }

    # --- processors: one hardcoded tenant_id tag per tenant ---
    for key in [k for k in list(processors) if k.startswith("attributes/tag_tenant_")]:
        del processors[key]
    for tenant_id in sorted(current):
        processors[f"attributes/tag_tenant_{tenant_id.replace('-', '_')}"] = {
            "actions": [{"key": "tenant_id", "action": "upsert", "value": tenant_id}]
        }

    # --- exporters: one hardcoded-X-Scope-OrgID set per tenant. The
    # shared otlp/tempo, otlphttp/loki, prometheusremotewrite exporters'
    # auth (headers_setter, from_context: tenant_id) reads the tenant
    # from CLIENT gRPC/HTTP context - but these mTLS receivers never get
    # that at all (tenant_id here is a hardcoded resource attribute the
    # processor above adds AFTER receipt, not client-supplied metadata,
    # and the migrated VMs no longer even send a tenant_id header).
    # Found live: every tenant's data was silently landing in Mimir/Loki
    # under headers_setter's own default_value ("anonymous") instead of
    # the real tenant - not a missing-data bug, a data-isolation one
    # (Grafana's per-tenant dashboards showed "No data" only because
    # they query their OWN tenant's Mimir/Loki partition, which never
    # actually received anything). A static `headers` map needs no
    # context at all - same "server binds the identity, not the client"
    # principle the receivers/processors above already use.
    for key in [k for k in list(exporters) if k.startswith(("prometheusremotewrite/tenant-", "otlphttp/loki/tenant-", "otlp/tempo/tenant-"))]:
        del exporters[key]
    for tenant_id in sorted(current):
        exporters[f"prometheusremotewrite/tenant-{tenant_id}"] = {
            "endpoint": "http://mimir-gateway.observability.svc:80/api/v1/push",
            "resource_to_telemetry_conversion": {"enabled": True},
            "headers": {"X-Scope-OrgID": tenant_id},
        }
        exporters[f"otlphttp/loki/tenant-{tenant_id}"] = {
            "logs_endpoint": "http://loki-gateway.observability.svc:80/otlp/v1/logs",
            "headers": {"X-Scope-OrgID": tenant_id},
        }
        exporters[f"otlp/tempo/tenant-{tenant_id}"] = {
            "endpoint": "tempo-distributor.observability.svc:4317",
            "tls": {"insecure": True},
            "headers": {"X-Scope-OrgID": tenant_id},
        }

    # --- pipelines: one traces/metrics/logs branch per tenant, using
    # that tenant's own hardcoded-header exporters above (NOT the shared
    # ones the non-mTLS pipelines use) - filter/reject_unknown_tenants is
    # deliberately NOT included here: tenant_id is hardcoded per
    # receiver, not client-supplied, so there's nothing left for that
    # allowlist to defend against on this path. ---
    for key in [k for k in list(pipelines) if k.startswith(("traces/tenant-", "metrics/tenant-", "logs/tenant-"))]:
        del pipelines[key]
    for tenant_id in sorted(current):
        tag_proc = f"attributes/tag_tenant_{tenant_id.replace('-', '_')}"
        pipelines[f"traces/tenant-{tenant_id}"] = {
            "receivers": [f"otlp/tenant-{tenant_id}"],
            "processors": ["memory_limiter", "k8sattributes", "resourcedetection", tag_proc, "batch"],
            "exporters": [f"otlp/tempo/tenant-{tenant_id}", "debug"],
        }
        pipelines[f"metrics/tenant-{tenant_id}"] = {
            "receivers": [f"otlp/tenant-{tenant_id}"],
            "processors": ["memory_limiter", "k8sattributes", tag_proc, "transform/strip_high_cardinality_metrics", "batch"],
            "exporters": [f"prometheusremotewrite/tenant-{tenant_id}", "debug"],
        }
        pipelines[f"logs/tenant-{tenant_id}"] = {
            "receivers": [f"otlp/tenant-{tenant_id}"],
            "processors": ["memory_limiter", "k8sattributes", "resourcedetection", tag_proc, "batch"],
            "exporters": [f"otlphttp/loki/tenant-{tenant_id}", "debug"],
        }

    dump_deduped(yaml, data, path, header="---\n")
    print(f"Updated {path} ({len(current)} per-tenant mTLS receivers/pipelines)")


# Resource attribute the gateway itself sets from the sending pod's
# namespace (k8sattributes/source in otel-gateway-collector.yaml). Any
# client-sent value is deleted before that processor runs.
GATEWAY_SOURCE_NAMESPACE_ATTR = "gateway.source_namespace"
# Namespace of the platform's own collectors (otel-agent fans node and
# pod logs out to many tenants via the tenant_id header) - the only
# source still trusted to choose its tenant itself.
TRUSTED_NAMESPACE = "observability"

# F20: AKS namespaces whose container logs belong to the platform tenant
# 4087 (cluster infrastructure). Every other namespace must be claimed by a
# manifest's k8s_namespaces, otherwise its logs are dropped. Keep in sync
# with manifests/schema.json (k8s_namespaces items "not" enum).
AGENT_PLATFORM_NAMESPACES = [
    "calico-system",
    "cert-manager",
    "default",
    "ingress-traefik",
    "kube-node-lease",
    "kube-public",
    "kube-system",
    "linkerd",
    "linkerd-viz",
    "observability",
    "openclaw",
    "opentelemetry-operator-system",
    "tigera-operator",
]


def update_gateway_namespace_routing(tenants, yaml: YAML):
    """
    F03: the shared otlp receiver no longer lets in-cluster workloads
    pick their own tenant. (The syslog receiver shares the logs entry
    pipeline but carries no client connection info, so its records
    always land in logs/unattributed - no sender uses it.) Each signal's entry pipeline ends
    in a routing connector keyed on the sending pod's namespace
    (GATEWAY_SOURCE_NAMESPACE_ATTR):
      - a namespace listed in a manifest's k8s_namespaces -> that
        tenant's own branch: hardcoded tenant tag + the per-tenant
        static-header exporters from update_gateway_tenant_mtls_receivers()
        (a client-set tenant_id is ignored);
      - TRUSTED_NAMESPACE -> <signal>/trusted, the old tenant_id-header
        chain (allowlist included);
      - anything else (unknown namespace, or no pod at all, e.g. traffic
        from outside the cluster) -> <signal>/unattributed, dropped.

    Needs the gateway to see the real client IP: linkerd's inbound proxy
    would otherwise hide it (podAnnotations skip-inbound-ports in
    otel-gateway-collector.yaml).
    """
    path = REPO_ROOT / "collector-gateway" / "otel-gateway-collector.yaml"
    data = yaml.load(path.read_text())
    config = data["spec"]["config"]
    pipelines = config["service"]["pipelines"]
    connectors = config.setdefault("connectors", {})

    owner = {}
    for t in tenants:
        for ns in t["k8s_namespaces"]:
            assert ns != TRUSTED_NAMESPACE, f"{t['tenant_id']}: namespace {ns!r} is reserved"
            assert re.fullmatch(r"[a-z0-9]([-a-z0-9]*[a-z0-9])?", ns), f"{t['tenant_id']}: bad namespace {ns!r}"
            assert ns not in owner, f"namespace {ns!r} claimed by both {owner[ns]} and {t['tenant_id']}"
            owner[ns] = t["tenant_id"]

    signals = {
        "traces": {"exporter": "otlp/tempo/tenant-{}", "trusted_exporter": "otlp/tempo", "extra": []},
        "metrics": {
            "exporter": "prometheusremotewrite/tenant-{}",
            "trusted_exporter": "prometheusremotewrite",
            "extra": ["transform/strip_high_cardinality_metrics"],
        },
        "logs": {"exporter": "otlphttp/loki/tenant-{}", "trusted_exporter": "otlphttp/loki", "extra": []},
    }

    for key in [k for k in list(pipelines) if re.fullmatch(r"(traces|metrics|logs)/ns-.+", k)]:
        del pipelines[key]

    for signal, cfg in signals.items():
        connector = f"routing/{signal}"
        trusted = f"{signal}/trusted"
        unattributed = f"{signal}/unattributed"
        table = [{
            "context": "resource",
            "condition": f'attributes["{GATEWAY_SOURCE_NAMESPACE_ATTR}"] == "{TRUSTED_NAMESPACE}"',
            "pipelines": [trusted],
        }]
        for ns, tenant_id in sorted(owner.items()):
            table.append({
                "context": "resource",
                "condition": f'attributes["{GATEWAY_SOURCE_NAMESPACE_ATTR}"] == "{ns}"',
                "pipelines": [f"{signal}/ns-{tenant_id}"],
            })
        connectors[connector] = {"default_pipelines": [unattributed], "table": table}

        pipelines[signal]["exporters"] = [connector]
        pipelines[trusted] = {
            "receivers": [connector],
            "processors": ["resource/strip_source_namespace", "attributes/tag_tenant", "filter/reject_unknown_tenants", *cfg["extra"], "batch"],
            "exporters": [cfg["trusted_exporter"], "debug"],
        }
        pipelines[unattributed] = {"receivers": [connector], "exporters": ["nop"]}
        for tenant_id in sorted(set(owner.values())):
            pipelines[f"{signal}/ns-{tenant_id}"] = {
                "receivers": [connector],
                "processors": [
                    "resource/strip_source_namespace",
                    f"attributes/tag_tenant_{tenant_id.replace('-', '_')}",
                    *cfg["extra"],
                    "batch",
                ],
                "exporters": [cfg["exporter"].format(tenant_id), "debug"],
            }

    dump_deduped(yaml, data, path, header="---\n")
    print(f"Updated {path} ({len(owner)} namespace->tenant routes)")


# G02 (FR-05): masking catalog applied by the gateway to every tenant's
# logs and traces, before anything reaches Loki/Tempo. (name, RE2 regex,
# replacement) - "$1"/"$2" keep a captured prefix such as "Bearer " or
# "password=". Credit cards are matched by IIN prefix and length only:
# OTTL can't run a Luhn check, so a 16-digit number starting with 4 is
# masked even if it isn't a valid card. Metrics are not masked - their
# attributes are labels, which instrumentation/schema/core.yaml's
# Cardinality Rule already keeps free of identifiers.
REDACTION_BASE = [
    ("email", r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "<redacted:email>"),
    ("iban", r"\b[A-Z]{2}[0-9]{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\b", "<redacted:iban>"),
    ("ahv", r"\b756\.?[0-9]{4}\.?[0-9]{4}\.?[0-9]{2}\b", "<redacted:ahv>"),
    ("card", r"\b(?:4[0-9]{3}|5[1-5][0-9]{2}|2[2-7][0-9]{2})(?:[ -]?[0-9]{4}){3}\b", "<redacted:card>"),
    ("card-amex", r"\b3[47][0-9]{2}[ -]?[0-9]{6}[ -]?[0-9]{5}\b", "<redacted:card>"),
    ("bearer", r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{8,}", "$1<redacted:token>"),
    ("url-credentials", r"(://[^:/\s@]+:)[^@/\s]+@", "$1<redacted>@"),
    (
        "secret-assignment",
        r"""(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|token)("?\s*[:=]\s*"?)[^"\s,;&]+""",
        "$1$2<redacted>",
    ),
]
# Attributes (and keys of structured log bodies) whose NAME marks them as
# a credential are deleted outright - their value has no "password="
# prefix the value patterns above could match. cvv/cvc: the Astronomy
# Shop's emitRawPii flag (demo 3.1) writes demo.payment.card_cvv and the
# full demo.payment.card_number into spans, and its bundled collector
# that would remove them is disabled here. The card value pattern above
# only knows Visa/Mastercard/Amex prefixes, so the key is deleted.
REDACTION_SENSITIVE_KEYS = (
    r"(?i)(^|[._-])(password|passwd|pwd|secret|client[_-]?secret|api[_-]?key|apikey|"
    r"access[_-]?token|refresh[_-]?token|token|authorization|cookie|set[_-]?cookie|cvv|cvc|card[_-]?number)$"
)
REDACTION_PROCESSOR = "transform/redact"


def _ottl_string(value: str) -> str:
    # OTTL string literal; "$" doubled because the collector config
    # expands ${...} itself before OTTL ever sees the string.
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + escaped.replace("$", "$$") + '"'


def _redaction_statements(rules, kind: str, condition: str = "") -> list[str]:
    """OTTL statements applying rules to log bodies (kind="body": string
    bodies, and the top-level values of structured map bodies) or to
    attribute maps (kind="attributes"). Values nested deeper than one
    level are not reached - OTTL's replace functions don't recurse."""

    def where(*conds):
        return " and ".join(c for c in (*conds, condition) if c)

    out = []
    for _name, regex, replacement in rules:
        pattern, repl = _ottl_string(regex), _ottl_string(replacement)
        if kind == "body":
            out.append(f"replace_pattern(body, {pattern}, {repl}) where {where('IsString(body)')}")
            out.append(f'replace_all_patterns(body, "value", {pattern}, {repl}) where {where("IsMap(body)")}')
        else:
            stmt = f'replace_all_patterns(attributes, "value", {pattern}, {repl})'
            out.append(f"{stmt} where {condition}" if condition else stmt)
    return out


def _sensitive_key_statements(kind: str) -> list[str]:
    keys = _ottl_string(REDACTION_SENSITIVE_KEYS)
    if kind == "body":
        return [f"delete_matching_keys(body, {keys}) where IsMap(body)"]
    return [f"delete_matching_keys(attributes, {keys})"]


def update_gateway_redaction(tenants, yaml: YAML):
    """
    G02 (FR-05): writes the transform/redact processor (REDACTION_BASE for
    everyone plus each manifest's own redaction.patterns, scoped to its
    tenants via the tenant_id record attribute every pipeline sets before
    this processor) and inserts it right before "batch" in every traces/
    and logs/ pipeline that exports somewhere. Runs last, after the other
    gateway generators created their pipelines.
    """
    path = REPO_ROOT / "collector-gateway" / "otel-gateway-collector.yaml"
    data = yaml.load(path.read_text())
    config = data["spec"]["config"]
    pipelines = config["service"]["pipelines"]

    log_stmts = (
        _sensitive_key_statements("body")
        + _sensitive_key_statements("attributes")
        + _redaction_statements(REDACTION_BASE, "body")
        + _redaction_statements(REDACTION_BASE, "attributes")
    )
    span_stmts = _sensitive_key_statements("attributes") + _redaction_statements(REDACTION_BASE, "attributes")
    event_stmts = list(span_stmts)
    for t in tenants:
        rules = [(p["name"], p["regex"], f"<redacted:{p['name']}>") for p in t["redaction_patterns"]]
        if not rules:
            continue
        cond = f'attributes["tenant_id"] == "{t["tenant_id"]}"'
        log_stmts += _redaction_statements(rules, "body", cond) + _redaction_statements(rules, "attributes", cond)
        span_stmts += _redaction_statements(rules, "attributes", cond)
        # Span events carry no tenant_id of their own - their span does.
        event_stmts += _redaction_statements(rules, "attributes", f'span.attributes["tenant_id"] == "{t["tenant_id"]}"')

    config["processors"][REDACTION_PROCESSOR] = {
        "error_mode": "ignore",
        "log_statements": [{"context": "log", "statements": log_stmts}],
        "trace_statements": [
            {"context": "span", "statements": span_stmts},
            {"context": "spanevent", "statements": event_stmts},
        ],
    }

    count = 0
    for name, pipeline in pipelines.items():
        processors = pipeline.get("processors") or []
        if not name.startswith(("traces/", "logs/")) or "batch" not in processors:
            continue
        if REDACTION_PROCESSOR in processors:
            processors.remove(REDACTION_PROCESSOR)
        processors.insert(processors.index("batch"), REDACTION_PROCESSOR)
        count += 1

    dump_deduped(yaml, data, path, header="---\n")
    print(f"Updated {path} (redaction in {count} pipelines)")


def update_agent_log_routing(tenants, yaml: YAML):
    """
    F20: container log routing of the 4087 node agent
    (instrumentation/platforms/4087-container-platform/config.yaml),
    generated from the manifests' k8s_namespaces - the same source the
    gateway's namespace routing uses, instead of a hand-maintained table.

    A DaemonSet serves the whole node, so its filelog receiver sees every
    namespace's container logs:
      - a tenant namespace -> logs/ns-<tenant_id> (exporter with that
        tenant's static tenant_id header)
      - AGENT_PLATFORM_NAMESPACES and node logs without a namespace
        (/var/log/syslog, /var/log/auth.log) -> logs/platform (4087's
        own tenant)
      - anything else -> logs/unattributed (dropped). Previously the
        default route, so a newly deployed but not yet onboarded
        namespace landed silently in the platform tenant and was readable
        by everyone with 4087 access. Dropped volume is visible as
        otelcol_exporter_sent_log_records{exporter="nop"}.
    """
    path = REPO_ROOT / "instrumentation" / "platforms" / "4087-container-platform" / "config.yaml"
    data = yaml.load(path.read_text())
    config = data["spec"]["config"]
    exporters = config["exporters"]
    pipelines = config["service"]["pipelines"]

    owner = {}
    for t in tenants:
        for ns in t["k8s_namespaces"]:
            assert ns not in AGENT_PLATFORM_NAMESPACES, f"{t['tenant_id']}: namespace {ns!r} is a platform namespace"
            owner[ns] = t["tenant_id"]

    table = [
        {
            "context": "resource",
            "condition": 'attributes["k8s.namespace.name"] == nil',
            "pipelines": ["logs/platform"],
        }
    ] + [
        {
            "context": "resource",
            "condition": f'attributes["k8s.namespace.name"] == "{ns}"',
            "pipelines": ["logs/platform"],
        }
        for ns in AGENT_PLATFORM_NAMESPACES
    ] + [
        {
            "context": "resource",
            "condition": f'attributes["k8s.namespace.name"] == "{ns}"',
            "pipelines": [f"logs/ns-{tenant_id}"],
        }
        for ns, tenant_id in sorted(owner.items())
    ]
    config["connectors"]["routing/logs"] = {
        "default_pipelines": ["logs/unattributed"],
        "error_mode": "ignore",
        "table": table,
    }

    for key in [k for k in list(exporters) if k.startswith("otlp/gateway-")]:
        del exporters[key]
    exporters["nop"] = {}
    for key in [k for k in list(pipelines) if k.startswith("logs/") and k != "logs/platform"]:
        del pipelines[key]
    pipelines["logs/unattributed"] = {"receivers": ["routing/logs"], "exporters": ["nop"]}
    for tenant_id in sorted(set(owner.values())):
        exporters[f"otlp/gateway-{tenant_id}"] = {
            "endpoint": "otel-gateway-collector.observability.svc:4317",
            "tls": {"insecure": True},
            "headers": {"tenant_id": tenant_id},
        }
        pipelines[f"logs/ns-{tenant_id}"] = {"receivers": ["routing/logs"], "exporters": [f"otlp/gateway-{tenant_id}"]}

    dump_deduped(yaml, data, path, header="---\n")
    print(f"Updated {path} ({len(owner)} tenant namespaces, {len(AGENT_PLATFORM_NAMESPACES)} platform namespaces)")


def regenerate_dashboards(manifests):
    # One dashboard per system now, not one per environment - see
    # generate-system-dashboard.py's own header comment for why (a
    # confirmed Grafana upstream limitation on nested folder
    # provisioning made per-env files+folders unreliable; environment
    # is an in-dashboard variable instead). Only writes for
    # currently-manifested systems - see cleanup_orphaned_dashboards()
    # below for the complementary removal side (the reverse of
    # onboarding - see scripts/create-offboarding-mr.py).
    generator = REPO_ROOT / "scripts" / "generate-system-dashboard.py"
    for path, _manifest in manifests:
        result = subprocess.run(
            [sys.executable, str(generator), "--manifest", str(path)],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(result.stdout, file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            sys.exit(1)
        print(result.stdout.strip())


def cleanup_orphaned_dashboards(manifests):
    """
    Deletes dashboard files left behind by a system that's no longer
    manifested (offboarded, or manually removed to reset to a
    "nothing onboarded" state) - the complement to regenerate_dashboards()
    above, which only ever adds/updates. Dashboards need a real file
    deletion here, not a tombstone: unlike Grafana's datasource
    provisioning (add/update-only, see _render_tombstone_configmap()),
    its dashboard provisioning already tracks file deletions correctly
    on its own - so removing the file is the right (and sufficient) fix.

    Filenames are `<system_id>-<slug-of-name>.json`, written by
    generate-system-dashboard.py's own `main()` - matched here by their
    leading `<system_id>-` only, not the full slug (a system's name, and
    therefore its slug, isn't known once its manifest is already gone).
    One dashboard per system now (not per environment), so a system is
    only an orphan once it has no manifest at all - not per-environment,
    unlike before.
    """
    valid_ids = {manifest["system_id"] for _, manifest in manifests}

    removed = 0
    for path in sorted((REPO_ROOT / "dashboards").glob("*.json")):
        match = re.match(r"(\d+)-", path.name)
        if match and match.group(1) not in valid_ids:
            path.unlink()
            removed += 1
            print(f"Removed orphaned dashboard {path.relative_to(REPO_ROOT)}")

    print(f"Cleaned up {removed} orphaned dashboard file(s)")


def main() -> None:
    manifests = load_manifests()
    tenants = collect_tenants(manifests)

    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    # Matches this repo's existing list-indentation style (e.g.
    # loki-values.yaml's schemaConfig.configs) so untouched sections
    # don't pick up a spurious reformatting diff.
    yaml.indent(mapping=2, sequence=4, offset=2)

    update_mimir_values(tenants, yaml)
    update_loki_values(tenants, yaml)
    update_tempo_values(tenants, yaml)
    update_pyroscope_values(tenants, yaml)
    update_ingestion_budgets(tenants, yaml)
    update_grafana_datasources(tenants, yaml)
    update_gateway_tenant_allowlist(tenants, yaml)
    update_tenant_client_certs(tenants, yaml)
    update_gateway_tenant_mtls_receivers(tenants, yaml)
    update_gateway_namespace_routing(tenants, yaml)
    update_gateway_redaction(tenants, yaml)
    update_agent_log_routing(tenants, yaml)
    regenerate_dashboards(manifests)
    cleanup_orphaned_dashboards(manifests)


if __name__ == "__main__":
    main()
