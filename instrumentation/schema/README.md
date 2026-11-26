# Schema

[← Back to the main README](../../README.md) - see
[`B10. Telemetry Schema`](../../README.md#b10-telemetry-schema) for the
full write-up.

This directory is the **one place** in the repo where the base
resource-attribute schema lives - [`core.yaml`](core.yaml).
Changes here apply to every platform and application; nothing else in
this repo defines a competing or overlapping base schema. Lives inside
[`instrumentation/`](../) as this layered model's own foundation - see
that directory's own README for why, rather than as a fourth, parallel
layer.

This is layer 1 of a 3-layer model:

1. **Schema** (here) - the base attributes every platform/app carries.
2. **Platform/runtime templates** ([`platforms/`](../platforms/)/
   [`middleware/`](../middleware/)) - one folder per platform type or
   middleware technology, each extending the base schema with what
   that platform/runtime actually emits.
3. **Application templates** ([`applications/`](../applications/)) -
   one folder per application, extending its own platform/runtime
   template with anything specific to that one app
   (`app.<service.name>.*`).

See [`instrumentation/README.md`](../README.md) for the index of every
platform/runtime/application template.
