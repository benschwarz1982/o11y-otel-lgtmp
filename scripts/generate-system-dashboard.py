#!/usr/bin/env python3
"""
Stamp out a per-system Grafana dashboard from one of the templates in
dashboards/templates/, using an onboarding manifest (see the
observability-otel-demo-onboarding repo) and the same budget formula as
calculate-ingestion-budget.py. Writes ONE file per system (not one per
environment) to dashboards/<system_id>-<slug-of-name>.json - the
dashboard itself carries an "env" template variable (labels
ENG/AT/PROD, built from exactly the environments this system's own
manifest lists) that switches which environment's datasources every
panel queries, via Grafana's native variable interpolation inside a
plain datasource-name string (e.g. "Mimir-1286-${env}") - every panel
in these templates already references its datasource by name, not by
a {type,uid} object, so this needed no panel-shape change, only the
resolved string.

Was one file per (system, environment) until found live that Grafana's
dashboard file-provisioner (sidecar.dashboards.foldersFromFilesStructure)
only reliably supports one folder level from its mount root - a
confirmed, still-open upstream limitation
(https://github.com/grafana/grafana/issues/107158: "only works one
folder deep... imported as /bar/dashboard removing all leading
folders"), which broke the `<env>/<system_id>` nested Grafana folder an
earlier version of this repo tried. Grafana folders are single-level
now (`<system_id>`, see terraform/environments/tenants/main.tf's
locals.dashboards) - environment moved from being a folder/filename
axis to an in-dashboard variable instead, which sidesteps the
limitation entirely (no folder nesting involved).

Which template a system gets, and its optional demo narrative, are read
from the manifest's own `dashboard_template`/`demo_narrative` fields
(see the onboarding repo's manifests/schema.json) - not decided here.
This script only knows how to *render* a template given a manifest; it
has no knowledge of which specific systems exist or how they're
configured, that's onboarding data and belongs in the onboarding repo,
not hardcoded into the platform repo. `dashboard_template` defaults to
applications/k8s-app.template.json (Kubernetes-pod-based systems) if
the manifest doesn't set one - systems differ too much in how they
emit telemetry (Kubernetes pod vs. Linux VM vs. Windows VM vs. SNMP
device, ...) to share one dashboard shape; a Kubernetes-pod dashboard
showing "Recent Traces" for a system that's pure host infrastructure
is empty/wrong, not just imperfect. See dashboards/templates/ for the
full catalog and this repo's README for what each one is for.

Usage:
    python3 scripts/generate-system-dashboard.py \
        --manifest /path/to/4087-cloud-container-plattform.yaml

The rendered dashboard's datasource references
("Mimir-<system_id>-${env}" etc.) resolve at Grafana-render time
against whichever environment's datasource triplet
scripts/provision.py's update_grafana_datasources() has provisioned for
that system - this script does not create those datasources itself,
running provision.py first (or via the onboarding repo's provision:apply
job) keeps the two in sync.
"""
import argparse
import json
import re
import sys
from pathlib import Path

import yaml

# Duplicated from calculate-ingestion-budget.py rather than imported - a
# hyphenated filename isn't a valid Python module name to import, and
# renaming it would break the documented `python3 scripts/calculate-
# ingestion-budget.py --app ...` command elsewhere. Keep these two dicts
# in sync with that script by hand if they ever change.
RETENTION_DAYS = {
    "eng": 10,
    "at": 30,
    "prod": 30,
}
SIZE_GB_PER_DAY = {
    "S": 1,
    "M": 10,
    "L": 25,
}

REPO_ROOT = Path(__file__).resolve().parent.parent
TEMPLATES_DIR = REPO_ROOT / "dashboards" / "templates"
OUTPUT_DIR = REPO_ROOT / "dashboards"

DEFAULT_TEMPLATE = "applications/k8s-app.template.json"


def load_manifest(path: Path) -> dict:
    return yaml.safe_load(path.read_text())


def slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def build_env_options(manifest: dict) -> str:
    # Grafana "custom" variable query syntax: "Label : value, Label :
    # value" - order controls display order and (absent an explicit
    # "current") which one Grafana pre-selects, so prod is sorted first
    # when present since it's the common demo default.
    envs = [entry["env"] for entry in manifest["environments"]]
    envs.sort(key=lambda e: (e != "prod", e))
    return ",".join(f"{env.upper()} : {env}" for env in envs)


def build_budget_table(manifest: dict) -> str:
    lines = []
    for entry in manifest["environments"]:
        env, size = entry["env"], entry["size"]
        daily_gb = SIZE_GB_PER_DAY[size]
        retention_days = RETENTION_DAYS[env]
        budget_gb = daily_gb * retention_days
        lines.append(
            f"**{env.upper()}**: {budget_gb} GB total "
            f"({daily_gb} GB/day x {retention_days} days retention, size `{size}`)"
        )
    return "\n\n".join(lines)


def substitute(node, substitutions: dict):
    """Replace placeholders in every string (and key) of a parsed JSON tree."""
    if isinstance(node, str):
        for placeholder, value in substitutions.items():
            node = node.replace(placeholder, value)
        return node
    if isinstance(node, list):
        return [substitute(item, substitutions) for item in node]
    if isinstance(node, dict):
        return {substitute(k, substitutions): substitute(v, substitutions) for k, v in node.items()}
    return node


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    system_id = manifest["system_id"]

    substitutions = {
        "__SYSTEM_ID__": system_id,
        "__SYSTEM_NAME__": manifest["name"],
        "__SYSTEM_TYPE__": manifest["type"],
        # Template literal, not a resolved value - Grafana interpolates
        # ${env} against the dashboard's own "env" variable at render
        # time, both in datasource-name strings and inside query/text
        # content (e.g. a PromQL label matcher or markdown "Tenant:"
        # line) that references it directly.
        "__TENANT_ID__": f"{system_id}-${{env}}",
        "__OWNER_TEAM__": manifest["owner"]["team"],
        "__OWNER_CONTACT__": manifest["owner"]["contact"],
        "__DATASOURCE_MIMIR__": f"Mimir-{system_id}-${{env}}",
        "__DATASOURCE_LOKI__": f"Loki-{system_id}-${{env}}",
        "__DATASOURCE_TEMPO__": f"Tempo-{system_id}-${{env}}",
        "__ENV_OPTIONS__": build_env_options(manifest),
        "__BUDGET_TABLE__": build_budget_table(manifest),
        "__DEMO_NARRATIVE__": manifest.get("demo_narrative", ""),
    }

    template_path = (TEMPLATES_DIR / manifest.get("dashboard_template", DEFAULT_TEMPLATE)).resolve()
    # The manifest value comes from a self-service request: never read a
    # file outside the template catalog (absolute path, "..").
    if not template_path.is_relative_to(TEMPLATES_DIR.resolve()) or not template_path.is_file():
        sys.exit(f"dashboard_template {manifest.get('dashboard_template')!r} is not a template under {TEMPLATES_DIR}")
    # F19: placeholders are replaced inside the parsed JSON's strings, not
    # in the raw template text - a quote or backslash in a manifest value
    # (name, team, demo_narrative) used to break or inject JSON.
    dashboard = substitute(json.loads(template_path.read_text()), substitutions)

    # Flat, one file per system - see this module's own docstring for
    # why environment is no longer a directory/filename axis. Filename
    # keeps the leading system_id (not env - there's only one file now,
    # but cleanup_orphaned_dashboards() and Terraform's own folder
    # extraction both still key off this leading token).
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / f"{system_id}-{slugify(manifest['name'])}.json"
    output_path.write_text(json.dumps(dashboard, indent=2) + "\n")
    print(f"Wrote {output_path.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
