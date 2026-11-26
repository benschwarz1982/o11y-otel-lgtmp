"""Manifest validation shared by validate-manifests.py and the self-service
scripts (create-onboarding-mr.py, create-update-mr.py): manifests/schema.json
plus the checks JSON Schema draft-07 can't express (F18)."""

import json
import re
from pathlib import Path

from jsonschema import Draft7Validator

SCHEMA_PATH = Path(__file__).resolve().parent.parent / "manifests" / "schema.json"


def manifest_errors(manifest) -> list[str]:
    """All problems with one manifest, as "<location>: <message>" strings."""
    schema = json.loads(SCHEMA_PATH.read_text())
    # format_checker: without it, "format": "email" is only an annotation.
    validator = Draft7Validator(schema, format_checker=Draft7Validator.FORMAT_CHECKER)
    errors = [
        f"{'/'.join(str(p) for p in e.path) or '(root)'}: {e.message}"
        for e in sorted(validator.iter_errors(manifest), key=lambda e: list(e.path))
    ]
    # The checks below assume the schema's structure - skip them until
    # the schema errors are fixed instead of crashing on wrong types.
    if errors:
        return errors

    envs = [e.get("env") for e in manifest.get("environments") or [] if isinstance(e, dict)]
    duplicates = sorted({env for env in envs if envs.count(env) > 1 and env is not None})
    if duplicates:
        errors.append(f"environments: env listed more than once: {', '.join(duplicates)}")

    namespaces = manifest.get("k8s_namespaces")
    if isinstance(namespaces, dict):
        unknown = sorted(set(namespaces) - set(envs))
        if unknown:
            errors.append(f"k8s_namespaces: env(s) not in environments: {', '.join(unknown)}")

    # G02: the gateway runs these as RE2 (OTTL). Python's re accepts a
    # superset, so also reject the constructs RE2 lacks.
    for i, rule in enumerate((manifest.get("redaction") or {}).get("patterns", [])):
        regex = rule["regex"]
        try:
            re.compile(regex)
        except re.error as e:
            errors.append(f"redaction/patterns/{i}/regex: invalid regex: {e}")
            continue
        if re.search(r"\(\?[=!]|\(\?<[=!]|\\[1-9]|\(\?P=|\(\?>|(?<!\\)[*+?}]\+", regex):
            errors.append(f"redaction/patterns/{i}/regex: lookarounds, backreferences, atomic groups and possessive quantifiers are not supported (RE2)")
        # RE2 knows only the inline flags i, m, s, U - no (?x), (?a), ...
        if any(set(flags) - set("imsU-") for flags in re.findall(r"\(\?([a-zA-Z-]+)[:)]", regex)):
            errors.append(f"redaction/patterns/{i}/regex: only the inline flags i, m, s and U are supported (RE2)")
        if re.search(r"(?<!\\)\\Z", regex):
            errors.append(f"redaction/patterns/{i}/regex: \\Z is not supported (RE2) - use \\z")
        # RE2 caps repetition counts at 1000 (Go regexp/syntax).
        counts = [int(n) for pair in re.findall(r"\{(\d+)(?:,(\d*))?\}", regex) for n in pair if n]
        if any(n > 1000 for n in counts):
            errors.append(f"redaction/patterns/{i}/regex: repetition count above 1000 (RE2 limit)")
        # The final check of RE2 compatibility is otelcol validate on the
        # generated gateway config (scripts/test-redaction.py, local).
    return errors
