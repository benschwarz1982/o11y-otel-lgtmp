#!/usr/bin/env python3
"""
G02 (FR-05): runs the gateway's generated transform/redact processor
(collector-gateway/otel-gateway-collector.yaml) in a local OTel Collector
over scripts/testdata/redaction-samples.yaml and checks every result.

Each sample goes through as log body and as log attribute "msg", so both
statement kinds are covered. Needs docker; the collector image is the
gateway's own (spec.image), so the test runs the exact OTTL version that
runs in the cluster.

Usage: scripts/test-redaction.py   (exit code 1 on any mismatch)
"""

import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
GATEWAY = REPO_ROOT / "collector-gateway" / "otel-gateway-collector.yaml"
SAMPLES = REPO_ROOT / "scripts" / "testdata" / "redaction-samples.yaml"


def plain(value: dict):
    """OTLP JSON AnyValue -> str / dict (string and kvlist values only)."""
    if "kvlistValue" in value:
        return {kv["key"]: plain(kv["value"]) for kv in value["kvlistValue"].get("values", [])}
    return value.get("stringValue")


def main() -> int:
    gateway = yaml.safe_load(GATEWAY.read_text())
    image = gateway["spec"]["image"]
    processor = gateway["spec"]["config"]["processors"]["transform/redact"]
    samples = yaml.safe_load(SAMPLES.read_text())["samples"]

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        work.chmod(0o777)
        with (work / "in.log").open("w") as f:
            for i, s in enumerate(samples):
                record = {"id": str(i), "msg": s["input"], "tenant_id": s.get("tenant", "0000-test")}
                record.update(s.get("attributes", {}))
                f.write(json.dumps(record) + "\n")
        config = {
            "receivers": {
                "filelog": {
                    "include": ["/w/in.log"],
                    "start_at": "beginning",
                    "operators": [
                        {"type": "json_parser"},
                        {"type": "copy", "from": "attributes.msg", "to": "body"},
                    ],
                }
            },
            "processors": {"transform/redact": processor},
            "exporters": {"file": {"path": "/w/out.json"}},
            "service": {
                "telemetry": {"logs": {"level": "warn"}},
                "pipelines": {"logs": {"receivers": ["filelog"], "processors": ["transform/redact"], "exporters": ["file"]}},
            },
        }
        (work / "config.yaml").write_text(yaml.safe_dump(config))
        name = f"test-redaction-{int(time.time())}"
        proc = subprocess.Popen(
            ["docker", "run", "--rm", "--name", name, "--user", "0", "-v", f"{work}:/w", image, "--config", "/w/config.yaml"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        results = {}
        deadline = time.time() + 60
        while time.time() < deadline and len(results) < len(samples):
            time.sleep(2)
            out = work / "out.json"
            if not out.exists():
                continue
            for line in out.read_text().splitlines():
                for rl in json.loads(line).get("resourceLogs", []):
                    for sl in rl.get("scopeLogs", []):
                        for rec in sl.get("logRecords", []):
                            attrs = {a["key"]: plain(a["value"]) for a in rec.get("attributes", [])}
                            results[attrs["id"]] = (plain(rec["body"]), attrs.get("msg"), attrs)
        subprocess.run(["docker", "stop", name], check=False, capture_output=True)
        try:
            _, err = proc.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
            _, err = proc.communicate()

    failures = 0
    for i, s in enumerate(samples):
        got = results.get(str(i))
        if got is None:
            print(f"MISSING  #{i}: {s['input']}")
            failures += 1
            continue
        body, attr, attrs = got
        # A structured (map) input becomes a map body; its copy in the
        # "msg" attribute is a nested map the processor doesn't reach.
        checks = [("body", body)] if isinstance(s["input"], dict) else [("body", body), ("attribute", attr)]
        for key in s.get("expect_absent", []):
            if key in attrs:
                print(f"FAIL     #{i}: attribute {key!r} not deleted (value {attrs[key]!r})")
                failures += 1
        for where, value in checks:
            if value != s["expect"]:
                print(f"FAIL     #{i} ({where}): {s['input']!r}\n         got:    {value!r}\n         expect: {s['expect']!r}")
                failures += 1
    if failures:
        if not results:
            print(err[-2000:], file=sys.stderr)
        print(f"{failures} failure(s) in {len(samples)} samples")
        return 1
    print(f"OK: {len(samples)} samples (body and attribute)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
