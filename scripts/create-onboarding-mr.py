#!/usr/bin/env python3
"""
Turn a set of GitLab CI/CD variables (typically supplied by a pipeline
trigger from the self-service onboarding form) into a new manifest, and
open a merge request for it - never merges anything itself, that's still
the platform operator's job (see README.md#onboarding-process).

Expected environment variables:
    SYSTEM_ID       - e.g. "4712" (from the architecture inventory tool)
    SYSTEM_TYPE     - "platform" or "application"
    SYSTEM_NAME     - e.g. "Checkout Service"
    OWNER_TEAM      - e.g. "Checkout Team"
    OWNER_CONTACT   - e.g. "checkout-team@example.com"
    COST_CENTER     - e.g. "CC-4021", for chargeback/showback
    DASHBOARD_TEMPLATE - subfolder-qualified filename under
        dashboards/templates/, e.g. "platforms/linux-host.template.json"
        - required, not inferred: found live that leaving this optional
        (with generate-system-dashboard.py's own "defaults to
        applications/k8s-app.template.json" fallback) meant every
        system onboarded through this form silently got the wrong
        dashboard shape unless a human caught it during MR review -
        there's no reliable signal in the other fields (system_id/type/
        name) to infer telemetry shape from. See manifests/schema.json's
        own description for the full catalog.
    PLATFORM_REFS_JSON - JSON array of platform system_ids this runs on
        (applications only), e.g. '["1286", "4139"]'
    ENVIRONMENTS_JSON - JSON array, e.g. '[{"env":"eng","size":"S"},{"env":"prod","size":"M"}]'

Plus these, automatically present in any GitLab CI job:
    CI_API_V4_URL, CI_PROJECT_ID, CI_DEFAULT_BRANCH

And one that is NOT automatically present, must be set by hand as a
masked/protected CI/CD variable:
    GITLAB_API_TOKEN - an access token (scope "api"), used instead of
        CI_JOB_TOKEN because CI_JOB_TOKEN reliably 404s on repository
        API endpoints (branches/commits) even for this same project - a
        long-standing, still-open GitLab platform limitation, not
        something fixable via project settings. Ideally a Project Access
        Token, but Project Access Token creation is disabled for this
        namespace with no self-service toggle, so a Personal Access
        Token is used instead. See README.md#onboarding-process for how
        to create it.

Refuses to run outside CI (needs the platform's API token to call back
into it as this pipeline).

On GitHub Actions (.github/workflows/onboarding.yml) the same script
opens a pull request instead (scm_client.py -> github_client.py); the
workflow sets CI_DEFAULT_BRANCH/CI_COMMIT_SHA and GITHUB_TOKEN.
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

REQUIRED_ENV = [
    "SYSTEM_ID",
    "SYSTEM_TYPE",
    "SYSTEM_NAME",
    "OWNER_TEAM",
    "OWNER_CONTACT",
    "COST_CENTER",
    "DASHBOARD_TEMPLATE",
    "ENVIRONMENTS_JSON",
]


class IndentedDumper(yaml.SafeDumper):
    """
    PyYAML's default dumper doesn't indent list items under their
    parent mapping key (e.g. "environments:\n- env: prod", dash at
    column 0) - found live: validate:yaml's yamllint flagged exactly
    that as a real indentation error on the first generated manifest.
    Standard PyYAML workaround (increase_indent's own indentless
    parameter defaults to true for sequences; forcing it false here
    makes list items indent two spaces under their key instead).
    """

    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)


def slugify(name: str) -> str:
    slug = name.strip().lower()
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    return slug.strip("-")


def build_manifest() -> dict:
    manifest = {
        "system_id": os.environ["SYSTEM_ID"],
        "type": os.environ["SYSTEM_TYPE"],
        "name": os.environ["SYSTEM_NAME"],
        "owner": {
            "team": os.environ["OWNER_TEAM"],
            "contact": os.environ["OWNER_CONTACT"],
        },
        "cost_center": os.environ["COST_CENTER"],
        "dashboard_template": os.environ["DASHBOARD_TEMPLATE"],
        "environments": json.loads(os.environ["ENVIRONMENTS_JSON"]),
    }
    platform_refs_json = os.environ.get("PLATFORM_REFS_JSON", "").strip()
    if platform_refs_json:
        manifest["platform_refs"] = json.loads(platform_refs_json)
    return manifest


def validate(manifest: dict) -> None:
    errors = manifest_errors(manifest)
    if errors:
        print("Manifest failed schema validation:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        sys.exit(1)


def target_path(manifest: dict) -> Path:
    subdir = "platforms" if manifest["type"] == "platform" else "applications"
    filename = f"{manifest['system_id']}-{slugify(manifest['name'])}.yaml"
    return Path("manifests") / subdir / filename


def main() -> None:
    missing = [v for v in REQUIRED_ENV if not os.environ.get(v)]
    if missing:
        print(f"Missing required variables: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)
    require_ci_token()

    manifest = build_manifest()
    validate(manifest)

    path = target_path(manifest)
    if path.exists():
        print(f"{path} already exists - this script only creates new systems, not updates. "
              f"Edit the existing file by hand / via a normal MR instead.", file=sys.stderr)
        sys.exit(1)
    # Same system_id under a different name (F18): the file name check above
    # doesn't see it.
    for existing in sorted(REPO_ROOT.glob("manifests/*/*.yaml")):
        if str((yaml.safe_load(existing.read_text()) or {}).get("system_id")) == manifest["system_id"]:
            print(f"system_id {manifest['system_id']} is already onboarded ({existing.relative_to(REPO_ROOT)}).", file=sys.stderr)
            sys.exit(1)

    branch_name = f"onboard/{manifest['system_id']}-{slugify(manifest['name'])}"
    default_branch = os.environ["CI_DEFAULT_BRANCH"]

    manifest_yaml = "---\n" + yaml.dump(manifest, Dumper=IndentedDumper, sort_keys=False, default_flow_style=False)

    # Generated files go into the same commit as the manifest - see
    # scripts/provisioning_sync.py. Done before creating the branch, so a
    # provision.py failure leaves nothing behind in GitLab.
    (REPO_ROOT / path).write_text(manifest_yaml)
    print("Running provision.py for the new manifest...")
    generated = provisioning_actions()

    print(f"Creating branch {branch_name}...")
    # Branch from the exact commit the generated files were computed
    # against, not the default branch's current tip - another merge in
    # between would otherwise make them stale (provision:check catches
    # that, but it would fail every such MR).
    base_ref = os.environ.get("CI_COMMIT_SHA", default_branch)
    base_sha = create_branch(branch_name, base_ref)

    print(f"Committing {path} and {len(generated)} generated file change(s)...")
    create_commit(
        branch_name,
        base_sha,
        f"Onboard {manifest['name']} ({manifest['system_id']})",
        [
            {"action": "create", "file_path": str(path), "content": manifest_yaml},
            *generated,
        ],
    )

    print("Opening merge request...")
    mr = create_merge_request(
        {
            "source_branch": branch_name,
            "target_branch": default_branch,
            "title": f"Onboard {manifest['name']} ({manifest['system_id']})",
            "description": (
                f"Automated onboarding request for **{manifest['name']}** "
                f"(`{manifest['system_id']}`, type `{manifest['type']}`).\n\n"
                f"Submitted via the self-service onboarding pipeline - "
                f"review and merge to provision it. See README.md#onboarding-process."
            ),
            "remove_source_branch": True,
        }
    )

    # No explicit POST /merge_requests/:iid/pipelines call here - tried
    # that (see README.md#known-pitfalls for the full story), but
    # GitLab's own auto-trigger turned out inconsistent in both
    # directions: sometimes it didn't fire on its own (the original
    # motivation), sometimes it did AND the explicit call also
    # succeeded, creating a genuine duplicate pipeline for the same
    # commit (found live). Trusting GitLab's default behavior is the
    # lesser problem of the two - a rare missing pipeline needs a manual
    # "Run pipeline" click on the MR; a duplicate silently wastes CI
    # minutes every single time.
    print(f"Merge request created: {mr['web_url']}")


if __name__ == "__main__":
    main()
