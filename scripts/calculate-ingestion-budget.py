#!/usr/bin/env python3
"""
Ingestion budget calculator for the observability platform.

Computes storage budgets and ingestion rate limits from an application name,
environment, and telemetry size class, and prints ready-to-use YAML override
snippets for Mimir, Loki, and Tempo.

Usage:
    python3 scripts/calculate-ingestion-budget.py --app checkout --env prod --size M
"""
import argparse

RETENTION_DAYS = {
    "eng": 10,
    "at": 30,
    "prod": 30,
}

SIZE_GB_PER_DAY = {
    "S": 1,
    "M": 10,
    "L": 25,
}

PEAK_FACTOR = 5  # Peak-load multiplier vs. the 24h average, adjust as needed


def compute(app: str, env: str, size: str):
    env = env.lower()
    size = size.upper()
    if env not in RETENTION_DAYS:
        raise ValueError(f"Unknown env '{env}', allowed: {list(RETENTION_DAYS)}")
    if size not in SIZE_GB_PER_DAY:
        raise ValueError(f"Unknown size '{size}', allowed: {list(SIZE_GB_PER_DAY)}")

    retention_days = RETENTION_DAYS[env]
    daily_gb = SIZE_GB_PER_DAY[size]
    total_budget_gb = daily_gb * retention_days

    avg_rate_mb_s = (daily_gb * 1024) / 86400
    burst_rate_mb_s = avg_rate_mb_s * PEAK_FACTOR

    tenant_id = f"{app}-{env}"

    return {
        "tenant_id": tenant_id,
        "retention_days": retention_days,
        "daily_gb": daily_gb,
        "total_budget_gb": round(total_budget_gb, 2),
        "avg_rate_mb_s": round(avg_rate_mb_s, 4),
        "burst_rate_mb_s": round(burst_rate_mb_s, 4),
    }


def render_yaml(result: dict):
    tenant = result["tenant_id"]
    retention_h = result["retention_days"] * 24
    rate_mb = result["burst_rate_mb_s"]
    burst_mb = round(rate_mb * 2, 4)

    print(f"# --- Budget for tenant '{tenant}' ---")
    print(f"# Total storage budget: {result['total_budget_gb']} GB "
          f"({result['daily_gb']} GB/day x {result['retention_days']} days)")
    print(f"# Avg ingestion rate: {result['avg_rate_mb_s']} MB/s, "
          f"Peak (x{PEAK_FACTOR}): {result['burst_rate_mb_s']} MB/s\n")

    print("## Loki (loki-values.yaml -> loki.runtimeConfig.overrides)")
    print(f'"{tenant}":')
    print(f"  ingestion_rate_mb: {rate_mb}")
    print(f"  ingestion_burst_size_mb: {burst_mb}")
    print(f"  retention_period: {retention_h}h\n")

    print("## Tempo (tempo-values.yaml -> globalOverrides.perTenantOverrides)")
    print(f"{tenant}:")
    print("  ingestion:")
    print(f"    rate_limit_bytes: {int(rate_mb * 1024 * 1024)}")
    print(f"    burst_size_bytes: {int(burst_mb * 1024 * 1024)}\n")

    print("## Mimir (mimir-values.yaml -> runtimeConfig.overrides, top-level)")
    print("# Note: Mimir limits by series/samples, not bytes.")
    print("# Values here are a rough approximation - calibrate with real series counts if needed.")
    print(f'"{tenant}":')
    print(f"  ingestion_rate: {int(rate_mb * 1000)}   # approximated samples/sec")
    print(f"  ingestion_burst_size: {int(burst_mb * 1000)}")
    print(f"  compactor_blocks_retention_period: {retention_h}h")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, help="Application name")
    parser.add_argument("--env", required=True, choices=["eng", "at", "prod"])
    parser.add_argument("--size", required=True, choices=["S", "M", "L"])
    args = parser.parse_args()

    result = compute(args.app, args.env, args.size)
    render_yaml(result)
