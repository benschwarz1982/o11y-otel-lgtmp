#!/usr/bin/env python3
"""
Demo break for UC4 (Multi-Tenancy: Ingestion Budget Enforcement) -
floods a tenant's Loki ingestion with synthetic log lines fast enough
to cross its own daily GB budget within a short demo window.

This is possible again (and reliably fast) now that the per-second
rate limit is generic and size-independent (scripts/provision.py's
GENERIC_INGESTION_RATE_MB) rather than tied to the tenant's own size
tier: under the old design, ANY tenant's fastest possible fill time was
a fixed 86400/PEAK_FACTOR seconds (~4.8h) regardless of size, since the
rate limit itself scaled down with a smaller daily budget - found live,
and the reason UC4 couldn't be demoed quickly before this
redesign. Now the generic ceiling (tens of MB/s) is the same for every
tenant, so a small tenant's tiny budget (4711-prod/Mitarbeiterverzeichnis,
S-tier, 1 GiB/day) fills in well under a minute at a modest, sustained
push rate - no artificial shortcut needed, this really is "push enough
real-shaped traffic, fast".

Loki (not Mimir/Tempo/Pyroscope) is the flood target: its push API is
plain JSON (no protobuf/Snappy encoding needed, unlike Mimir remote-write
- see scripts/ingestion-midnight-snapshot.py's own hand-rolled encoder
for why that one needs it), and 4711-prod's own real workload
(Tomcat's catalina.out via the logs pipeline) already skews toward Loki
ingestion volume day to day, making a Loki-shaped spike the most
narratively consistent choice for this specific demo tenant.

Talks to Loki via `kubectl port-forward` (must already be running,
started by the caller - see .gitlab-ci.yml's demo:uc4-break job), not
any public endpoint - matching every other ad-hoc push this repo's own
scripts make against this cluster.
"""
import argparse
import json
import sys
import threading
import time
import urllib.error
import urllib.request


def push_batch(url: str, tenant: str, line: str, count: int) -> int:
    now_ns = time.time_ns()
    values = [[str(now_ns + i), line] for i in range(count)]
    payload = json.dumps(
        {"streams": [{"stream": {"job": "demo-uc4-flood"}, "values": values}]}
    ).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        method="POST",
        headers={"Content-Type": "application/json", "X-Scope-OrgID": tenant},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()
    return len(payload)


def worker(url, tenant, line, count, end_time, counters, lock):
    while time.time() < end_time:
        try:
            n = push_batch(url, tenant, line, count)
            with lock:
                counters["bytes"] += n
                counters["pushed"] += 1
        except urllib.error.HTTPError:
            # 429 (rate_limited) is expected once the tenant's own daily
            # budget enforcer throttles it mid-flood - keep going, the
            # point of this script is to *cause* that.
            with lock:
                counters["failed"] += 1
        except (urllib.error.URLError, OSError, TimeoutError) as e:
            print(f"push failed: {e}", file=sys.stderr)
            with lock:
                counters["failed"] += 1


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=3100, help="local port from `kubectl port-forward svc/loki-gateway <port>:80`")
    parser.add_argument("--tenant", default="4711-prod")
    parser.add_argument(
        "--duration",
        type=int,
        default=150,
        help="seconds to flood for - confirmed live this throughput settles around ~8.5 MB/s "
        "regardless of worker count past ~8 (the single kubectl port-forward tunnel itself "
        "appears to be the ceiling, not Loki), so 150s (~1.27 GB attempted) gives 4711-prod's "
        "1 GiB/day S-tier budget a safe margin over the default single `kubectl port-forward` setup",
    )
    parser.add_argument("--line-bytes", type=int, default=8000)
    parser.add_argument("--lines-per-batch", type=int, default=100)
    parser.add_argument("--workers", type=int, default=8, help="concurrent pushers - a single synchronous urllib request per batch is network-round-trip-bound, too slow alone to fill even a small daily budget within a short demo window; diminishing returns confirmed live past ~8")
    args = parser.parse_args()

    url = f"http://localhost:{args.port}/loki/api/v1/push"
    line = "X" * args.line_bytes
    end_time = time.time() + args.duration
    counters = {"bytes": 0, "pushed": 0, "failed": 0}
    lock = threading.Lock()

    threads = [
        threading.Thread(target=worker, args=(url, args.tenant, line, args.lines_per_batch, end_time, counters, lock))
        for _ in range(args.workers)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    print(
        f"Pushed {counters['pushed']} batch(es) across {args.workers} worker(s) "
        f"(~{counters['bytes'] / (1024 * 1024):.1f} MB accepted-attempt volume, "
        f"{counters['failed']} rejected/failed) of synthetic log lines to {args.tenant} over {args.duration}s."
    )


if __name__ == "__main__":
    main()
