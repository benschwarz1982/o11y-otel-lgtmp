#!/usr/bin/env python3
"""
Turn an update request (typically supplied by a pipeline trigger from
the self-service onboarding form's "Update" mode) into a merge request
that changes an already-onboarded system's owner and/or environments/
ingestion budget - never merges anything itself, that's still the
platform operator's job (see README.md#onboarding-process).

Deliberately narrower than onboarding: `system_id`, `type`, `name`,
`cost_center`, `dashboard_template`, `demo_narrative`, and
`platform_refs` are treated as fixed identity, carried over unchanged
from the existing manifest - only `owner` and `environments` are
replaced with the submitted values.
Requesters shouldn't have to re-enter (or risk accidentally changing)
fields like the system's name just to resize an ingestion budget.

Expected environment variables:
    UPDATE_SYSTEM_ID  - e.g. "4712" (deliberately a different variable
        name than SYSTEM_ID/OFFBOARDING_SYSTEM_ID, same reasoning as
        those two - keeps all three jobs' rules mutually exclusive)
    OWNER_TEAM        - e.g. "Checkout Team"
    OWNER_CONTACT     - e.g. "checkout-team@example.com"
    ENVIRONMENTS_JSON - JSON array, e.g. '[{"env":"eng","size":"S"},{"env":"prod","size":"M"}]'
        - replaces the manifest's entire environments list (not merged
        entry-by-entry), matching how the form's checkboxes submit the
        requester's complete current desired state each time.

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
    python3 scripts/create-update-mr.py
"""
import json
import os
import re
import sys
from pathlib import Path

import yaml
from manifest_validation import manifest_errors
from provisioning_sync import provisioning_actions
from scm_client import (
    create_branch,
    create_commit,
    create_merge_request,
    require_ci_token,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_SUBDIRS = ["platforms", "applications"]

REQUIRED_ENV = ["UPDATE_SYSTEM_ID", "OWNER_TEAM", "OWNER_CONTACT", "ENVIRONMENTS_JSON"]


class IndentedDumper(yaml.SafeDumper):
    """See create-onboarding-mr.py's own copy of this class for why."""

    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)


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
              f"nothing to update (not onboarded, or already offboarded).", file=sys.stderr)
        sys.exit(1)
    if len(matches) > 1:
        print(f"Ambiguous: multiple manifests match system_id {system_id!r}: "
              f"{[str(m) for m in matches]}", file=sys.stderr)
        sys.exit(1)
    return matches[0]


def validate(manifest: dict) -> None:
    errors = manifest_errors(manifest)
    if errors:
        print("Manifest failed schema validation:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    missing = [v for v in REQUIRED_ENV if not os.environ.get(v)]
    if missing:
        print(f"Missing required variables: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)
    require_ci_token()

    system_id = os.environ["UPDATE_SYSTEM_ID"].strip()
    path = find_manifest(system_id)
    manifest = yaml.safe_load(path.read_text())
    name = manifest.get("name", system_id)

    manifest["owner"] = {
        "team": os.environ["OWNER_TEAM"],
        "contact": os.environ["OWNER_CONTACT"],
    }
    manifest["environments"] = json.loads(os.environ["ENVIRONMENTS_JSON"])
    validate(manifest)

    branch_name = f"update/{system_id}-{slugify(name)}"
    default_branch = os.environ["CI_DEFAULT_BRANCH"]
    relative_path = path.relative_to(REPO_ROOT)

    manifest_yaml = "---\n" + yaml.dump(manifest, Dumper=IndentedDumper, sort_keys=False, default_flow_style=False)

    # Generated files go into the same commit as the manifest - see
    # scripts/provisioning_sync.py.
    path.write_text(manifest_yaml)
    print("Running provision.py for the updated manifest...")
    generated = provisioning_actions()

    print(f"Creating branch {branch_name}...")
    # Branch from the exact commit the generated files were computed
    # against, not the default branch's current tip - another merge in
    # between would otherwise make them stale (provision:check catches
    # that, but it would fail every such MR).
    base_ref = os.environ.get("CI_COMMIT_SHA", default_branch)
    base_sha = create_branch(branch_name, base_ref)

    print(f"Updating {relative_path} and {len(generated)} generated file change(s)...")
    create_commit(
        branch_name,
        base_sha,
        f"Update {name} ({system_id})",
        [
            {"action": "update", "file_path": str(relative_path), "content": manifest_yaml},
            *generated,
        ],
    )

    print("Opening merge request...")
    mr = create_merge_request(
        {
            "source_branch": branch_name,
            "target_branch": default_branch,
            "title": f"Update {name} ({system_id})",
            "description": (
                f"Automated update request for **{name}** (`{system_id}`) - "
                f"new owner/environments below.\n\n"
                f"Submitted via the self-service onboarding pipeline's update "
                f"mode - review and merge to apply it. See "
                f"README.md#onboarding-process.\n\n"
                f"**Owner**: {manifest['owner']['team']} "
                f"({manifest['owner']['contact']})\n\n"
                f"**Environments**: "
                + ", ".join(f"{e['env']}={e['size']}" for e in manifest["environments"])
            ),
            "remove_source_branch": True,
        }
    )

    print(f"Merge request created: {mr['web_url']}")


if __name__ == "__main__":
    main()
