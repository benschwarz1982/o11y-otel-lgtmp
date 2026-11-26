# Demo

## Demo

### Use Cases

Each use case ties platforms/applications together and demonstrates
specific observability disciplines. Redesigned down to 4 (from an
earlier 6, briefly 5) with three explicit goals: cover all three OTel
signal types where realistic, split cleanly between a Platform
Engineer audience and an Application Engineer audience (rather than
always blending platform+app into one use case), and demonstrate
multi-tenant ingestion budget enforcement, not just per-system
telemetry. UC4 (Object Storage Usage, 4015) was dropped outright
rather than replaced - 4015 stays onboarded and monitored, it just no
longer anchors a dedicated Use Case or alert - and the former UC5
(Multi-Tenancy: Ingestion Budget Enforcement) moved up to fill the
UC4 slot. The `Alerts` column pulls straight from
[`alerting/`](../alerting) - see that directory's own README for the
full rule definitions and the [Runbook](#runbook) below for how to
actually fire/clear each one live.

| # | Use Case | Systems Involved | Audience | Metrics | Logs | Traces | Alerts |
|---|---|---|---|---|---|---|---|
| UC1 | [Linux CPU Saturation](#uc1---linux-cpu-saturation) | 1286 | Platform Engineer | Host CPU metric - verified | — | — (pure infrastructure, no request context) | 1286 host CPU > 80% (1m) |
| UC2 | [Windows Service Crash](#uc2---windows-service-crash) | 1229 | Platform Engineer | — | Windows Event Log errors (Print Spooler crash, `detected_level=ERROR`) - verified | — (pure infrastructure, no request context) | 1229 Print Spooler service crashed (1m) |
| UC3 | [Kubernetes Microservices](#uc3---kubernetes-microservices) | 4720 | Application Engineer | — | — | Distributed traces across the checkout flow - verified (shipping service latency spike from `intlShippingSlowdown`, visible in Explore → Tempo and via a slow-request-count spanmetrics alert) | 4720 shipping requests > 500ms present (1m) |
| UC4 | [Multi-Tenancy: Ingestion Budget Enforcement](#uc4---multi-tenancy-ingestion-budget-enforcement) | cross-tenant (Operator view; `4711-prod` is this use case's own demo tenant, otherwise unrelated to it - see [Runbook](#runbook)) | Operator/SRE | Per-signal daily ingestion volume vs. each tenant's own signal-specific budget (`demo_ingestion_since_midnight`, `demo_ingestion_daily_budget`) - the same metrics the "Operator: Tenant Ingestion Budget" dashboard uses; enforcement (throttling, day-rollover) live-verified this session, including the demo break/fix flow itself | — | — | Tenant ingestion budget exhausted (>100% of daily budget) |

Systems no longer anchoring a use case of their own after this
redesign (1294, 4015, 4087, 4721, 4722) stay fully instrumented and
monitored in the fleet - they just don't get a dedicated presenter
walkthrough, and their own alert rules were removed (see
[`alerting/README.md`](../alerting/README.md)) rather than kept around
unused.

### Runbook

For the presenter: how to actually run each Use Case live, end to end.
Every alert here evaluates every `interval: 1m` with a `for: 1m`
sustained-duration requirement, deliberately tuned short for a live
demo (see [`alerting/`](../alerting)) - the underlying PromQL rate
windows are `[1m]` too, not the more usual `[5m]`, so the metric
itself reflects a sudden load change within about a minute instead of
slowly ramping over five. Every break job takes **~1-2 minutes** to
visibly transition Normal → Pending → Firing on Grafana's own Alerting
page - confirmed live end to end on UC1 (Pending → Firing in 69s).
Every fix job clears its alert on the very next evaluation
(within ~1 minute).

**Set each dashboard's own time range to something narrow (e.g. "Last
15 minutes") before starting a break job** - found live: dashboard
panels use Grafana's `$__rate_interval` variable, which scales with
the *dashboard's currently selected time range*, not the fixed `[1m]`
window the alert rules themselves use. Left at a wide default range
(e.g. "Last 6 hours"), a 1-2 minute CPU/latency/error spike gets
smoothed into near-invisibility on the panel even though the alert
itself fires correctly off its own, narrower window - confirmed live
(the same query showing 100% over `[1m]` showed only ~50% over
`[30m]`, and would be far flatter still over a 6h-scaled interval).
The alert firing is unaffected either way; this is purely about the
panel staying visually convincing during a live demo.

Apps to have open:

| App | System ID | URL |
|---|---|---|
| OTel Astronomy Shop Demo | 4720 | https://astronomy-shop.sre.example.com/ |
| Kundenverwaltung | 4721 | https://kundenverwaltung.sre.example.com/customers (REST API, no root page - also `/health`) |
| Spesenabrechnung | 4722 | `http://<vm-windows-demo public IP>:8080/expenses` (REST API, no root page - also `/health`; IP via `az vm show -g <resource-group> -n vm-windows-demo -d --query publicIps -o tsv`) - not its own Use Case anymore, no longer UC4's demo tenant either (see UC4's own Runbook entry) |

Mitarbeiterverzeichnis (4711, on `vm-rocky-demo`) has no dedicated step
below - UC1 is 1286 (the platform) only now, no app to open.

#### UC1 - Linux CPU Saturation

1. Show 1286's own dashboard (`Grafana → Dashboards → 1286 → Linux
   Basis`, `env` dropdown defaults to `PROD`), point out the CPU panel.
2. Run **`demo:uc1-break`** - starts 2 CPU-spin loops on
   `vm-rocky-demo` (its 2 vCPUs).
3. Watch the CPU panel climb; after ~1-2 min, **"1286 Linux Basis -
   host CPU > 80%"** fires on the Alerting page.
4. Run **`demo:uc1-fix`** - kills the loops. CPU drops immediately;
   the alert clears on its next evaluation.

#### UC2 - Windows Service Crash

1. Show 1229's own dashboard (`Grafana → Dashboards → 1229 → Windows
   Server Basis`), point out the **Windows Event Log: Error** panel
   and **Recent Logs** below it - that's what this UC's alert watches.
2. Run **`demo:uc2-break`** - starts a loop on `vm-windows-demo` that
   kills the Print Spooler service's process every 30s, so it keeps
   crashing and restarting.
3. After ~1-2 min, **"1229 Windows Server Basis - Print Spooler
   service crashed"** fires; the Error panel and Recent Logs both show
   repeated Service Control Manager error events.
4. Run **`demo:uc2-fix`** - stops the loop; Spooler stabilizes, and
   the alert clears once no new errors appear within its lookback
   window (~2 min).

#### UC3 - Kubernetes Microservices

1. As a customer, open the real shop (https://astronomy-shop.sre.example.com/),
   add an item to the cart and check out with a non-US shipping
   address - note it completes quickly.
2. Run **`demo:uc3-break`** - flips the shop's own `flagd` feature
   flag `intlShippingSlowdown` from `off` to `5sec` (the chart's own
   official fault-injection mechanism, not something this repo
   builds), then restarts `flagd` itself - found live: despite its
   own `fsnotify` file watcher, this deployment's `flagd` doesn't
   actually pick up a ConfigMap content change without a restart (its
   config volume looks seeded once at pod start, not a live mount).
3. Repeat the same checkout - "the customer reports the site is
   slow": the shipping step now visibly hangs for ~5s.
4. In Grafana, open the Astronomy Shop dashboard's **Recent Traces**
   panel (or Explore → Tempo, datasource `tempo-4720-prod`, query
   `{resource.service.name="shipping" && duration > 1s}`) and find a
   checkout trace with it - a long `shipping` span shows exactly where
   the delay is. On the dashboard's **Request Latency (p95) by
   Endpoint/Operation** panel, filter/look for the **`POST
   /ship-order`** series specifically - that's the one span_name that
   actually spikes (~4.1s p95 while broken), every other series on
   that panel stays fast throughout.
5. Check Grafana's Alerting page: **"4720 OTel Astronomy Shop Demo -
   shipping requests slow"** fires within ~1-2 min, same ballpark as
   this repo's other Use Cases. This rule counts actual slow requests
   rather than computing a percentile - found live that a p95-based
   query (an earlier version of this rule) was structurally unable to
   register the problem reliably, since `intlShippingSlowdown` only
   ever affects international-address checkouts, a minority of the
   shop's overall traffic; a percentile query gets diluted back to
   "normal" the moment any of the majority of unaffected (US-address)
   requests lands as the most recent sample. Counting instead of
   percentile-ing fixes this: every slow request registers and stays
   counted for a full 3-minute window regardless of how much fast
   traffic happens alongside it.
6. Run **`demo:uc3-fix`** - flips the flag back to `off` and restarts
   `flagd` the same way.
7. Verify from both sides: the same checkout is fast again, Tempo's
   new traces show a normal-length shipping span, and the alert clears
   within ~3 min once your own slow checkout ages out of the rule's
   3-minute counting window (assuming no other slow checkout lands in
   the meantime).

#### UC4 - Multi-Tenancy: Ingestion Budget Enforcement

1. Show the "Operator: Tenant Ingestion Budget" dashboard (`Grafana →
   Dashboards → shared`) - explain per-tenant daily budgets and this
   being an Operator/SRE-facing, cross-tenant view rather than one
   system's own dashboard.
2. Run **`demo:uc4-break`** - floods Mitarbeiterverzeichnis's
   (`4711-prod`) Loki ingestion for ~2.5 minutes
   (`scripts/demo-uc4-flood.py`), enough to push its Loki daily usage
   past its own actual 1 GiB/day (S-tier) Loki budget - each signal has
   its own independent daily budget now (NFR-05), so this flood only
   throttles 4711-prod's Loki traffic, not its Mimir/Tempo/Pyroscope
   traffic too. This is possible quickly now that the per-second rate
   limit is generic and size-independent - unlike the old size-tied
   design, where any tenant's fastest possible fill time was a fixed
   ~4.8h regardless of size (found live before this redesign).
3. Allow up to ~2 more minutes after the flood - the daily-budget
   enforcer only checks every 2 minutes (not a real-time gate the way
   the per-second rate limit is, so some overshoot past 100% before it
   catches up is expected and normal). Once it does, **"Tenant/signal
   has used up its daily ingestion budget"** fires for `4711-prod`'s
   `loki` signal specifically, and the `ingestion-midnight-snapshot`
   enforcer throttles `4711-prod`'s rate/burst limit to near-zero on
   Loki's runtime ConfigMap ONLY - its Mimir/Tempo/Pyroscope traffic
   keeps flowing unaffected (NFR-05: each signal is its own independent
   budget now, see the "Budget enforcement" section above) - visible as
   real discards on the dashboard's Loki Discard Rate panel only.
4. Run **`demo:uc4-fix`** - un-throttles `4711-prod` on every signal
   it's currently throttled on (just Loki, in this walkthrough) and
   resets its daily usage back to 0% on all four signals immediately (a
   one-off in-cluster Job running the enforcer script's own
   `--reset-tenant` mode), without waiting for the next real midnight
   rollover. The alert clears on its next evaluation.

A real midnight rollover (not exercised by `demo:uc4-fix`, which is a
manual shortcut for demo pacing) restores every currently-throttled
tenant the same way, automatically, once a day.
