# \<Platform Type\> - Instrumentation Guide

[← Back to the template index](../../README.md) - layer 2 of the
[3-layer model](../../schema/README.md) (schema → **platform/
runtime** → application).

Copy this folder to `instrumentation/platforms/<system-id>-<your-platform>/`
when adding a new platform type - every folder here gets a numeric
prefix, live or not (see [`1286-linux-basis/`](../1286-linux-basis/)/
[`1229-windows-basis/`](../1229-windows-basis/) for a live-demo
example, [`4015-filestorage/`](../4015-filestorage/)/
[`1285-mainframe-basis/`](../1285-mainframe-basis/) for reference-only
ones). If this platform isn't actually deployed anywhere in this
repo's fleet, the prefix is illustrative only, not a real onboarded
system ID - say so explicitly in the "⚠️ Not part of this demo's live
fleet" banner (see either reference-only guide's own banner for the
wording), so nobody mistakes it for one:

1. **Architecture** - a diagram: what this platform emits, how it
   reaches the collector, how the collector reaches the gateway.
2. **Installation** - how the collector gets onto/near this platform.
3. **Collector Config Walkthrough** - receivers/processors/exporters,
   and which [`schema/core.yaml`](../../schema/core.yaml)
   Core Schema attributes this template sets (`platform.type`/
   `platform.vendor` at minimum).
4. **Validation** - how to confirm data actually reaches Mimir/Loki/
   Tempo under the right tenant.
5. **Known Pitfalls** - link to [README.md's Known
   Pitfalls](../../../docs/known-pitfalls.md#known-pitfalls) for anything already
   found live; add new entries there too, not only here, if you find
   one.
6. **Rollout Checklist** - a short table, same shape as the other
   guides.

If this platform is actually part of this demo's fixed fleet, also add
a `config.yaml` alongside this `README.md` (the real, placeholder-
substitutable template - see `1286-linux-basis/config.yaml` for the pattern) and
a corresponding entry in `schema/core.yaml`'s
`platform_extensions`. If it's reference-only (not deployed here),
open with the same "⚠️ Not part of this demo's live fleet" banner
`4015-filestorage/README.md`/`1285-mainframe-basis/README.md` use, and list it under
`platform_extensions.not_present` instead.

Update [`instrumentation/README.md`](../../README.md)'s platform table with
the new entry either way.
