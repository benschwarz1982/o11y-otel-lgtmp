#!/usr/bin/env python3
"""Validate every manifest under manifests/{platforms,applications}/ against manifests/schema.json."""

import sys
from pathlib import Path

import yaml
from manifest_validation import manifest_errors

REPO_ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    manifest_files = sorted(
        (REPO_ROOT / "manifests" / "platforms").glob("*.yaml")
    ) + sorted((REPO_ROOT / "manifests" / "applications").glob("*.yaml"))

    if not manifest_files:
        print("No manifest files found under manifests/platforms/ or manifests/applications/")
        return 0

    had_errors = False
    owners = {}
    for path in manifest_files:
        data = yaml.safe_load(path.read_text())
        errors = manifest_errors(data)
        # system_id must be unique across all manifests (F18) - it is the
        # tenant ID and derives ports, dashboards and file names.
        system_id = data.get("system_id") if isinstance(data, dict) else None
        if system_id is not None:
            if system_id in owners:
                errors.append(f"system_id: {system_id} already used by {owners[system_id]}")
            else:
                owners[system_id] = path.relative_to(REPO_ROOT)
        if errors:
            had_errors = True
            print(f"FAIL: {path.relative_to(REPO_ROOT)}")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"OK:   {path.relative_to(REPO_ROOT)}")

    return 1 if had_errors else 0


if __name__ == "__main__":
    sys.exit(main())
