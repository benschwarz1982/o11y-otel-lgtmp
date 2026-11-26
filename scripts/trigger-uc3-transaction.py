#!/usr/bin/env python3
"""
Demo trigger for UC3 (Kubernetes Microservices) - fires one request at
the OTel Astronomy Shop Demo's own public URL with a
`correlation.transaction_id` OTel Baggage entry, so a presenter can
show that ID surviving across a real, multi-service call (unlike UC1/
UC2/UC4/UC6, which are all single-service-to-its-own-backend flows and
already fully captured by trace context alone - see
instrumentation/schema/core.yaml's Baggage Schema section for why this
Use Case is the only one this actually applies to).

What this script can and can't promise:
  - The W3C `baggage` header it sends is correctly formatted and will
    be picked up by the shop's own OTel SDK context-propagation layer
    (this repo's apps never override OTEL_PROPAGATORS, so the default
    `tracecontext,baggage` applies everywhere, and nothing in this
    repo's own config disables it for the shop either) - the baggage
    entry genuinely reaches every hop's in-process context.
  - Whether any of the shop's downstream services *also* copy that
    baggage entry onto their own span/log attributes (making it
    directly searchable in Tempo/Loki, not just present in the live
    context) depends entirely on the upstream open-telemetry-demo
    chart's own per-service OTel SDK configuration - this repo doesn't
    own or customize that chart's application source. **Verified live,
    negative result**: triggered a real request this way, then
    searched every known span attribute name on tenant 4720-prod in
    Tempo - none contain "correlation". The upstream chart has no
    baggage-to-span-attribute processor wired into any service
    (tracked upstream as open-telemetry/opentelemetry-demo#1572, open/
    unimplemented) - not a bug in this script, and not fixable from
    this repo without editing that chart's own per-service source
    across several languages.

Usage:
    python3 scripts/trigger-uc3-transaction.py --url https://astronomy-shop.<dns-zone>/
"""
import argparse
import urllib.request
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--url",
        required=True,
        help="URL to hit - the shop's own public homepage, "
        "which already fans out to several of its own backend services on a plain "
        "GET, no checkout-flow request body needed)",
    )
    args = parser.parse_args()

    transaction_id = str(uuid.uuid4())
    request = urllib.request.Request(
        args.url,
        headers={"baggage": f"correlation.transaction_id={transaction_id}"},
    )

    print(f"Requesting {args.url} with correlation.transaction_id={transaction_id}")
    with urllib.request.urlopen(request, timeout=15) as response:
        print(f"HTTP {response.status}")

    print()
    print(f"correlation.transaction_id: {transaction_id}")
    print(
        "This value will NOT show up as a searchable span attribute in Tempo - "
        "verified live, the shop's own services don't copy baggage onto spans "
        "(tracked upstream as open-telemetry/opentelemetry-demo#1572, see this "
        "script's own docstring). For the demo, show the `baggage` request header "
        "surviving in the browser/curl request itself instead."
    )


if __name__ == "__main__":
    main()
