#!/usr/bin/env python3
"""
Checks the Mimir ruler rules under rules/ (G03/G04/G08):

1. promtool check rules on every rule file (Mimir's source_tenants group
   field, which promtool doesn't know, is stripped first),
2. promtool test rules on rules/<tenant>/tests/*.test.yaml,
3. a tenant's "calendar" recording rules at the real dates in
   rules/<tenant>/tests/calendar-cases.yaml: promtool unit tests always
   start at the Unix epoch, so each formula is inlined with the case's
   timestamp in place of time() and evaluated as a promtool expression
   test.

Tests live in the tenant's own directory, so offboarding (which deletes
rules/<tenant>/) removes them too.

promtool: from PATH (CI image), else the pinned image via docker.
"""

import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
RULES_DIR = REPO_ROOT / "rules"
PROMTOOL_IMAGE = "prom/prometheus:v3.16.0"  # keep in sync with ci/images/Dockerfile


def promtool(args: list[str], mount: Path) -> subprocess.CompletedProcess:
    """Runs promtool with every path argument relative to mount."""
    if shutil.which("promtool"):
        cmd = ["promtool", *[str(mount / a) if a.endswith(".yaml") else a for a in args]]
    else:
        cmd = ["docker", "run", "--rm", "-v", f"{mount}:/m:ro", "--entrypoint", "promtool", PROMTOOL_IMAGE,
               *[f"/m/{a}" if a.endswith(".yaml") else a for a in args]]
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def calendar_test_file(tmp: Path, cases_file: Path) -> str:
    rules = {}
    for rule_file in sorted(cases_file.parent.parent.glob("*.yaml")):
        for group in yaml.safe_load(rule_file.read_text())["groups"]:
            if group["name"] == "calendar":
                rules = {r["record"]: " ".join(r["expr"].split()) for r in group["rules"]}
    if not rules:
        sys.exit(f"{cases_file}: no 'calendar' rule group in {cases_file.parent.parent}")

    def inline(expr: str, ts: int) -> str:
        # Replace references to earlier calendar records by their formula.
        for _ in range(5):
            for name, body in rules.items():
                expr = re.sub(rf"(?<![\w:]){re.escape(name)}(?![\w:])", f"({body})", expr)
        return expr.replace("time()", str(ts))

    tests = []
    for case in yaml.safe_load(cases_file.read_text())["cases"]:
        ts = int(datetime.fromisoformat(case["at"]).timestamp())
        exprs = []
        for key, value in case.items():
            if key == "at":
                continue
            record = next(n for n in rules if n.split(":")[1] == key)
            exprs.append({"expr": inline(rules[record], ts), "eval_time": "0m", "exp_samples": [{"labels": "{}", "value": value}]})
        tests.append({"name": f"calendar at {case['at']}", "promql_expr_test": exprs})
    path = tmp / f"calendar-{cases_file.parent.parent.name}.test.yaml"
    path.write_text(yaml.safe_dump({"rule_files": [], "evaluation_interval": "1m", "tests": tests}, sort_keys=False, width=1000))
    return path.name


def main() -> int:
    failed = False
    with tempfile.TemporaryDirectory() as tmp_name:
        tmp = Path(tmp_name)
        tmp.chmod(0o755)
        # Mirror of rules/ without Mimir's source_tenants (unknown to
        # promtool), used by the checks and unit tests below.
        mirror = tmp / "rules"
        files = []
        for src in sorted(RULES_DIR.glob("*/*.yaml")) + sorted(RULES_DIR.glob("*/tests/*.yaml")):
            dst = mirror / src.relative_to(RULES_DIR)
            dst.parent.mkdir(parents=True, exist_ok=True)
            for d in (dst.parent, dst.parent.parent):
                d.chmod(0o755)
            if src.parent.name == "tests":
                dst.write_text(src.read_text())
            else:
                data = yaml.safe_load(src.read_text())
                for g in data["groups"]:
                    g.pop("source_tenants", None)
                dst.write_text(yaml.safe_dump(data, sort_keys=False))
                files.append(dst.relative_to(mirror).as_posix())
            dst.chmod(0o644)

        # 1. syntax/semantics of every rule file
        r = promtool(["check", "rules", *files], mirror)
        print(r.stdout.strip() or r.stderr.strip())
        failed |= r.returncode != 0

        # 2. unit tests (rule_files paths are relative to the test file)
        for test in sorted(mirror.glob("*/tests/*.test.yaml")):
            rel = test.relative_to(mirror).as_posix()
            r = promtool(["test", "rules", rel], mirror)
            print(f"{rel}: {'OK' if r.returncode == 0 else 'FAILED'}")
            if r.returncode != 0:
                print(r.stdout + r.stderr)
            failed |= r.returncode != 0

        # 3. calendar formulas at real dates
        for cases_file in sorted(RULES_DIR.glob("*/tests/calendar-cases.yaml")):
            cal = calendar_test_file(tmp, cases_file)
            (tmp / cal).chmod(0o644)
            r = promtool(["test", "rules", cal], tmp)
            print(f"{cases_file.relative_to(RULES_DIR)}: {'OK' if r.returncode == 0 else 'FAILED'}")
            if r.returncode != 0:
                print(r.stdout + r.stderr)
            failed |= r.returncode != 0
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
