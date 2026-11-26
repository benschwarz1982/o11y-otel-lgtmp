#!/usr/bin/env python3
"""
Turn an offboarding request (typically supplied by a pipeline trigger
from the self-service onboarding form's "Offboarding" mode) into a
manifest-deleting merge request - never merges anything itself, that's
still the platform operator's job (see README.md#onboarding-process).
Reverse of scripts/create-onboarding-mr.py, same GitLab API pattern.

Expected environment variable:
    OFFBOARDING_SYSTEM_ID - e.g. "4712" (deliberately a different
        variable name than SYSTEM_ID, not an ACTION=offboard flag
        alongside it - keeps onboarding:create-mr's own $SYSTEM_ID-gated
        rule untouched, no risk of the two jobs' rules ever both/neither
        matching a given trigger call)

Plus these, automatically present in any GitLab CI job:
    CI_API_V4_URL, CI_PROJECT_ID, CI_DEFAULT_BRANCH

And one that is NOT automatically present, must be set by hand as a
masked/protected CI/CD variable (same one onboarding:create-mr uses):
    GITLAB_API_TOKEN - see README.md#onboarding-process for how to
        create it; NOT CI_JOB_TOKEN, same 404-on-repository-API-endpoints
        reason as that script.

Refuses to run outside CI (needs the platform's API token to call back
into it as this pipeline).

On GitHub Actions (.github/workflows/onboarding.yml) the same script
opens a pull request instead (scm_client.py -> github_client.py); the
workflow sets CI_DEFAULT_BRANCH/CI_COMMIT_SHA and GITHUB_TOKEN.

Usage:
    python3 scripts/create-offboarding-mr.py
"""
import os
import re
import sys
from pathlib import Path

import yaml
from provisioning_sync import provisioning_actions
from scm_client import (
    create_branch,
    create_commit,
    create_merge_request,
    require_ci_token,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_SUBDIRS = ["platforms", "applications"]


def slugify(name: str) -> str:
    slug = name.strip().lower()
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    return slug.strip("-")


def find_manifest(system_id: str) -> Path:
    matches = []
    for sub in MANIFEST_SUBDIRS:
        matches.extend((REPO_ROOT / "manifests" / sub).glob(f"{system_id}-*.yaml"))
    if not matches:
        print(f"No manifest found for system_id {system_id!r} under manifests/{{platforms,applications}}/ - "
              f"nothing to offboard (already removed, or never onboarded).", file=sys.stderr)
        sys.exit(1)
    if len(matches) > 1:
        print(f"Ambiguous: multiple manifests match system_id {system_id!r}: "
              f"{[str(m) for m in matches]}", file=sys.stderr)
        sys.exit(1)
    return matches[0]


def main() -> None:
    system_id = os.environ.get("OFFBOARDING_SYSTEM_ID", "").strip()
    if not system_id:
        print("Missing required variable: OFFBOARDING_SYSTEM_ID", file=sys.stderr)
        sys.exit(1)
    require_ci_token()

    path = find_manifest(system_id)
    manifest = yaml.safe_load(path.read_text())
    name = manifest.get("name", system_id)

    branch_name = f"offboard/{system_id}-{slugify(name)}"
    default_branch = os.environ["CI_DEFAULT_BRANCH"]
    relative_path = path.relative_to(REPO_ROOT)

    # Generated files (tombstones, removed dashboards/certs/limits) go into
    # the same commit as the manifest deletion - see
    # scripts/provisioning_sync.py.
    path.unlink()
    print("Running provision.py without the manifest...")
    generated = provisioning_actions()

    print(f"Creating branch {branch_name}...")
    # Branch from the exact commit the generated files were computed
    # against, not the default branch's current tip - another merge in
    # between would otherwise make them stale (provision:check catches
    # that, but it would fail every such MR).
    base_ref = os.environ.get("CI_COMMIT_SHA", default_branch)
    base_sha = create_branch(branch_name, base_ref)

    print(f"Deleting {relative_path}, {len(generated)} generated file change(s)...")
    create_commit(
        branch_name,
        base_sha,
        f"Offboard {name} ({system_id})",
        [
            {"action": "delete", "file_path": str(relative_path)},
            *generated,
        ],
    )

    print("Opening merge request...")
    mr = create_merge_request(
        {
            "source_branch": branch_name,
            "target_branch": default_branch,
            "title": f"Offboard {name} ({system_id})",
            "description": (
                f"Automated offboarding request for **{name}** "
                f"(`{system_id}`).\n\n"
                f"Submitted via the self-service onboarding pipeline's offboarding mode - "
                f"review and merge to remove it. Its Mimir/Loki ingestion budget, gateway "
                f"allowlist entry, and dashboard will be removed on the next `onboarding:apply` "
                f"run; its Grafana datasources will be tombstoned (Grafana's own datasource "
                f"provisioning can't delete them outright). See README.md#onboarding-process."
            ),
            "remove_source_branch": True,
        }
    )

    # No explicit POST /merge_requests/:iid/pipelines call here - see
    # create-onboarding-mr.py's own comment for why (found live: called
    # both ways, ended up with a genuine duplicate pipeline once).

    print(f"Merge request created: {mr['web_url']}")


if __name__ == "__main__":
    main()
