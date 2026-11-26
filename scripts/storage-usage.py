#!/usr/bin/env python3
"""
G06 (FR-09): measured object-storage volume per tenant and signal, for
showback. Runs hourly as the storage-usage CronJob
(terraform/environments/observability-stack/main.tf).

Lists every current blob (no old versions, no soft-deleted blobs) of the
four telemetry containers via the Blob REST API, with a read/list-only
account SAS (never the account key; in the cluster a file mounted from
the Key Vault by the CSI driver, G12), and attributes its size to a
tenant by path:

  mimir-blocks/<tenant>/...                    metrics
  loki-chunks/<tenant>/... and index/<table>/<tenant>/...   logs
  tempo-traces/<tenant>/...                    traces
  pyroscope-data/blocks/<shard>/<tenant>/...   profiles

Anything else (Pyroscope's not yet compacted multi-tenant segments,
bucket-level metadata) is reported as tenant="unattributed".

Pushes demo_storage_bytes{tenant, signal} and, per tenant,
demo_storage_budget_bytes{tenant} (the "storage" key scripts/provision.py
writes into ingestion-daily-budgets.yaml) to Mimir, reusing the
remote-write encoder and budget reader of ingestion-midnight-snapshot.py
(mounted next to this file as snapshot.py). Stdlib only.
"""

import importlib.util
import os
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

CONTAINERS = {
    "mimir-blocks": "metrics",
    "loki-chunks": "logs",
    "tempo-traces": "traces",
    "pyroscope-data": "profiles",
}
TENANT_RE = re.compile(r"^(?:[1-9][0-9]{3}-(?:prod|at|eng)|anonymous)$")
USAGE_METRIC = "demo_storage_bytes"
BUDGET_METRIC = "demo_storage_budget_bytes"


def _load_snapshot_helpers():
    here = Path(__file__).resolve().parent
    for candidate in (here / "snapshot.py", here / "ingestion-midnight-snapshot.py"):
        if candidate.exists():
            spec = importlib.util.spec_from_file_location("snapshot", candidate)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
    raise FileNotFoundError("snapshot.py (ingestion-midnight-snapshot.py) not found next to this script")


def tenant_of(container: str, name: str) -> str:
    parts = name.split("/")
    if container == "pyroscope-data":
        candidate = parts[2] if parts[0] == "blocks" and len(parts) > 2 else ""
    elif container == "loki-chunks" and parts[0] == "index":
        candidate = parts[2] if len(parts) > 2 else ""
    else:
        candidate = parts[0]
    return candidate if TENANT_RE.match(candidate) else "unattributed"


def list_blobs(account: str, container: str, sas: str):
    """Yields (name, size) for every current blob in container."""
    marker = ""
    while True:
        query = {"restype": "container", "comp": "list", "maxresults": "5000"}
        if marker:
            query["marker"] = marker
        url = f"https://{account}.blob.core.windows.net/{container}?{urllib.parse.urlencode(query)}&{sas.lstrip('?')}"
        with urllib.request.urlopen(url, timeout=60) as resp:
            root = ET.fromstring(resp.read())
        for blob in root.iter("Blob"):
            yield blob.findtext("Name"), int(blob.findtext("Properties/Content-Length") or 0)
        marker = root.findtext("NextMarker") or ""
        if not marker:
            return


def main() -> int:
    account = os.environ["STORAGE_ACCOUNT"]
    # G12: in the cluster the SAS is a file mounted from the Key Vault by
    # the Secrets Store CSI driver; STORAGE_SAS for local runs.
    sas_file = os.environ.get("STORAGE_SAS_FILE")
    sas = Path(sas_file).read_text().strip() if sas_file else os.environ["STORAGE_SAS"]
    snapshot = _load_snapshot_helpers()

    budgets = {}
    if os.path.exists(snapshot.DAILY_BUDGETS_PATH):
        budgets, _, _ = snapshot.load_daily_budgets()
    else:
        print(f"WARNING: {snapshot.DAILY_BUDGETS_PATH} missing - pushing usage without budgets", file=sys.stderr)

    # Every onboarded tenant (and "unattributed") gets a sample per signal,
    # 0 when it has no blobs - otherwise deleted data would keep showing
    # its last volume until the series goes stale.
    usage = defaultdict(int)
    for tenant in [*budgets, "unattributed"]:
        for signal in CONTAINERS.values():
            usage[(tenant, signal)] = 0
    for container, signal in CONTAINERS.items():
        for name, size in list_blobs(account, container, sas):
            usage[(tenant_of(container, name), signal)] += size

    rows = [(USAGE_METRIC, {"tenant": tenant, "signal": signal}, float(size)) for (tenant, signal), size in sorted(usage.items())]
    rows += [(BUDGET_METRIC, {"tenant": tenant}, float(b["storage"])) for tenant, b in sorted(budgets.items()) if "storage" in b]

    snapshot.push_metrics(rows)
    total = sum(usage.values())
    print(f"pushed {len(rows)} series, {total / 1024**3:.2f} GiB in {len(CONTAINERS)} containers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
