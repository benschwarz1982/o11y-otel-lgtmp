"""
GitHub entry point for self-service requests: reads the request (JSON,
from the self-service issue form or the workflow_dispatch input), maps
it onto the variables the GitLab pipeline passes, and runs the matching
create-{onboarding,update,offboarding}-mr.py, which opens a pull request.

The request is untrusted input (anyone allowed to open the issue writes
it): only the known keys are passed on, every value must be a string,
and the create-* scripts validate the resulting manifest against
manifests/schema.json before anything is committed.

Usage (inside .github/workflows/onboarding.yml):
    python3 scripts/self-service-request.py --event "$GITHUB_EVENT_PATH"
    python3 scripts/self-service-request.py --request '<json>'

Prints the pull request URL to $GITHUB_OUTPUT as `pr_url`.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
TEMPLATES = SCRIPTS.parent / "dashboards" / "templates"
SYSTEM_ID = re.compile(r"[1-9][0-9]{3}")

# Request key -> script. The keys are the GitLab CI variable names, so the
# same create-* scripts serve both platforms.
MODES = {
    "SYSTEM_ID": "create-onboarding-mr.py",
    "UPDATE_SYSTEM_ID": "create-update-mr.py",
    "OFFBOARDING_SYSTEM_ID": "create-offboarding-mr.py",
}
ALLOWED_KEYS = set(MODES) | {
    "SYSTEM_TYPE",
    "SYSTEM_NAME",
    "OWNER_TEAM",
    "OWNER_CONTACT",
    "COST_CENTER",
    "DASHBOARD_TEMPLATE",
    "PLATFORM_REFS_JSON",
    "ENVIRONMENTS_JSON",
}
MAX_VALUE_LENGTH = 2000


def request_from_issue(event_path: str) -> str:
    """The JSON block of the issue form's `request` field."""
    event = json.loads(Path(event_path).read_text())
    body = (event.get("issue") or {}).get("body") or ""
    match = re.search(r"```(?:json)?\s*\n(.*?)\n```", body, re.DOTALL)
    if match:
        return match.group(1)
    # Issue forms render a textarea without `render:` as plain text under
    # its "### <label>" heading.
    match = re.search(r"###[^\n]*\n+(\{.*\})", body, re.DOTALL)
    if not match:
        sys.exit("No JSON request found in the issue body - use the self-service form.")
    return match.group(1)


def parse(raw: str) -> dict[str, str]:
    try:
        request = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.exit(f"Request is not valid JSON: {e}")
    if not isinstance(request, dict):
        sys.exit("Request must be a JSON object.")
    unknown = sorted(set(request) - ALLOWED_KEYS)
    if unknown:
        sys.exit(f"Unknown request keys: {', '.join(unknown)}")
    for key, value in request.items():
        if not isinstance(value, str) or len(value) > MAX_VALUE_LENGTH:
            sys.exit(f"{key} must be a string of at most {MAX_VALUE_LENGTH} characters.")
    modes = [key for key in MODES if request.get(key, "").strip()]
    if len(modes) != 1:
        sys.exit(f"Exactly one of {', '.join(MODES)} must be set.")
    # IDs end up in file globs and branch names, the template in a file
    # path: check them here, before any script uses them.
    if not SYSTEM_ID.fullmatch(request[modes[0]].strip()):
        sys.exit(f"{modes[0]} must be a 4-digit system ID.")
    template = request.get("DASHBOARD_TEMPLATE")
    if template is not None and template not in dashboard_templates():
        sys.exit(f"DASHBOARD_TEMPLATE must be one of: {', '.join(sorted(dashboard_templates()))}")
    return request


def dashboard_templates() -> set[str]:
    """The template catalog, as paths relative to dashboards/templates/."""
    return {p.relative_to(TEMPLATES).as_posix() for p in TEMPLATES.rglob("*.template.json")}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--event", help="GitHub event payload (issues event)")
    source.add_argument("--request", help="request JSON (workflow_dispatch)")
    args = parser.parse_args()

    request = parse(request_from_issue(args.event) if args.event else args.request)
    script = next(MODES[key] for key in MODES if request.get(key, "").strip())

    env = {k: v for k, v in os.environ.items() if k not in ALLOWED_KEYS}
    env.update(request)
    result = subprocess.run(
        [sys.executable, str(SCRIPTS / script)],
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode != 0:
        sys.exit(result.returncode)

    match = re.search(r"Merge request created: (\S+)", result.stdout)
    if match and os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as out:
            out.write(f"pr_url={match.group(1)}\n")


if __name__ == "__main__":
    main()
