#!/usr/bin/env python3
"""
Syncs rules/<tenant>/*.yaml (G03 SLOs, G04 baselines, G08 status model)
into the Mimir ruler - one ruler namespace "repo" per tenant, so rule
groups created by hand in Grafana (other namespaces) are never touched.

For every tenant directory: uploads each group (create or replace) and
deletes groups in "repo" that are no longer in the files. Tenants that
still have a "repo" namespace in the ruler but no directory any more
(offboarded system, deleted SLOs) lose that namespace.

Talks to the ruler directly (its config API and the admin listing
/ruler/rule_groups, which the Mimir gateway does not route). In CI:
`kubectl port-forward svc/mimir-ruler` (tenants:rollout).

Usage: scripts/sync-mimir-rules.py [--url http://localhost:8080] [--dry-run]
"""

import argparse
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
RULES_DIR = REPO_ROOT / "rules"
NAMESPACE = "repo"


def request(url: str, method: str = "GET", tenant: str | None = None, body: bytes | None = None) -> tuple[int, bytes]:
    headers = {"Content-Type": "application/yaml"}
    if tenant:
        headers["X-Scope-OrgID"] = tenant
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def desired_rules() -> dict[str, dict[str, dict]]:
    """{tenant: {group name: group}} from rules/<tenant>/*.yaml."""
    out = {}
    for tenant_dir in sorted(p for p in RULES_DIR.iterdir() if p.is_dir()):
        groups = {}
        for f in sorted(tenant_dir.glob("*.yaml")):
            for g in yaml.safe_load(f.read_text())["groups"]:
                if g["name"] in groups:
                    sys.exit(f"{tenant_dir.name}: rule group {g['name']!r} defined twice")
                groups[g["name"]] = g
        out[tenant_dir.name] = groups
    return out


def current_repo_groups(base: str) -> dict[str, set[str]]:
    """{tenant: {group names in namespace repo}} across all tenants."""
    status, body = request(f"{base}/ruler/rule_groups")
    if status != 200:
        sys.exit(f"GET /ruler/rule_groups: HTTP {status}: {body[:300]!r}")
    data = yaml.safe_load(body) or {}
    return {tenant: {g["name"] for g in namespaces.get(NAMESPACE, [])} for tenant, namespaces in data.items() if NAMESPACE in namespaces}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost:8080", help="Mimir ruler base URL")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    base = args.url.rstrip("/")
    ns_url = f"{base}/prometheus/config/v1/rules/{NAMESPACE}"

    desired = desired_rules()
    current = current_repo_groups(base)
    errors = 0

    for tenant, groups in desired.items():
        for name, group in groups.items():
            print(f"{tenant}: upsert {name}")
            if not args.dry_run:
                status, body = request(ns_url, "POST", tenant, yaml.safe_dump(group, sort_keys=False).encode())
                if status not in (200, 202):
                    print(f"  ERROR HTTP {status}: {body[:500]!r}", file=sys.stderr)
                    errors += 1
        for name in sorted(current.get(tenant, set()) - set(groups)):
            print(f"{tenant}: delete {name}")
            if not args.dry_run:
                status, body = request(f"{ns_url}/{urllib.parse.quote(name, safe='')}", "DELETE", tenant)
                if status not in (200, 202, 404):
                    print(f"  ERROR HTTP {status}: {body[:300]!r}", file=sys.stderr)
                    errors += 1

    for tenant in sorted(set(current) - set(desired)):
        print(f"{tenant}: delete namespace {NAMESPACE} (no rules/{tenant}/ any more)")
        if not args.dry_run:
            status, body = request(ns_url, "DELETE", tenant)
            if status not in (200, 202, 404):
                print(f"  ERROR HTTP {status}: {body[:300]!r}", file=sys.stderr)
                errors += 1

    print(f"{'dry run: ' if args.dry_run else ''}{sum(len(g) for g in desired.values())} groups in {len(desired)} tenants, {errors} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
