#!/usr/bin/env python3
"""
Keep the files scripts/provision.py generates in sync with the manifests
inside the merge request that changes them, instead of a bot commit
pushed to main after the merge.

Before, tenants:apply ran provision.py on main after every merge and
pushed the result straight back to main. main was therefore briefly
inconsistent after every merge (manifest in, generated files not yet),
reviewers never saw the generated changes, and the pipeline needed a
token allowed to push to main.

Now:
  - scripts/create-{onboarding,update,offboarding}-mr.py apply their
    manifest change to the CI checkout, call provisioning_actions(),
    and put the resulting generated files into the same commit as the
    manifest (see those scripts).
  - `python3 scripts/provisioning_sync.py --check` (CI job
    provision:check in merge request pipelines, and tenants:apply on
    main) fails if the committed generated files differ from what
    provision.py produces for the committed manifests.

Works purely on file contents (snapshot before/after), so it needs no
git binary in the job image. provision.py is deterministic (same
manifests in, same files out - verified: two runs on a consistent main
produce no change).

Usage:
    python3 scripts/provisioning_sync.py --check

Exit codes: 0 up to date, 3 out of date (the regenerated files are left
in the working tree), anything else = provision.py itself failed.
"""
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
EXIT_OUT_OF_DATE = 3

# Everything provision.py writes or deletes. Single source of truth -
# tenants:apply's artifacts list in .gitlab-ci.yml must cover the same
# paths.
GENERATED_PATHS = [
    "helm/values/mimir-tenant-overrides.yaml",
    "helm/values/loki-tenant-overrides.yaml",
    "helm/values/tempo-tenant-overrides.yaml",
    "helm/values/pyroscope-tenant-overrides.yaml",
    "helm/values/ingestion-daily-budgets.yaml",
    "collector-gateway/otel-gateway-collector.yaml",
    "instrumentation/platforms/4087-container-platform/config.yaml",
    "datasources",
    "dashboards",
    "tls-certs",
    # G03/G04/G08: status model and business-service rules depend on the
    # onboarded tenants (scripts/generate-rules.py --no-slo below); slo/
    # because offboarding deletes the system's SLO sources.
    "rules",
    "slo",
]


def snapshot() -> dict[str, bytes]:
    """Content of every file under GENERATED_PATHS, keyed by repo-relative path."""
    files = {}
    for rel in GENERATED_PATHS:
        path = REPO_ROOT / rel
        if path.is_file():
            files[rel] = path.read_bytes()
        elif path.is_dir():
            for f in sorted(path.rglob("*")):
                if f.is_file():
                    files[f.relative_to(REPO_ROOT).as_posix()] = f.read_bytes()
    return files


def run_provision() -> None:
    result = subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts" / "provision.py")],
        cwd=REPO_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(f"provision.py failed (exit {result.returncode})")
    result = subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts" / "generate-rules.py"), "--no-slo"],
        cwd=REPO_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(f"generate-rules.py failed (exit {result.returncode})")


def diff(before: dict[str, bytes], after: dict[str, bytes]) -> list[dict]:
    """GitLab commit API actions turning `before` into `after`."""
    actions = []
    for rel in sorted(before.keys() | after.keys()):
        if rel not in after:
            actions.append({"action": "delete", "file_path": rel})
        elif rel not in before:
            actions.append({"action": "create", "file_path": rel, "content": after[rel].decode()})
        elif before[rel] != after[rel]:
            actions.append({"action": "update", "file_path": rel, "content": after[rel].decode()})
    return actions


def provisioning_actions() -> list[dict]:
    """
    Run provision.py against the current working tree (with the caller's
    manifest change already applied to it) and return the generated-file
    changes as GitLab commit API actions.
    """
    before = snapshot()
    run_provision()
    return diff(before, snapshot())


def main() -> None:
    if sys.argv[1:] != ["--check"]:
        sys.exit(__doc__)
    actions = provisioning_actions()
    if not actions:
        print("Generated provisioning files are up to date with the manifests.")
        return
    print("Generated provisioning files are out of date with the manifests:", file=sys.stderr)
    for a in actions:
        print(f"  {a['action']:6} {a['file_path']}", file=sys.stderr)
    print(
        "\nRun `python3 scripts/provision.py` and commit the result in this branch. "
        "(Merge requests from the onboarding/update/offboarding pipelines include it "
        "automatically; after a rebase onto a newer main, regenerate.)",
        file=sys.stderr,
    )
    sys.exit(EXIT_OUT_OF_DATE)


if __name__ == "__main__":
    main()
