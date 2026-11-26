# Application Templates

[← Back to the template index](../README.md) - layer 3 of the
[3-layer model](../schema/README.md) (schema → platform/runtime →
**application**). Builds on top of a
[platform](../platforms/)/[middleware](../middleware/) template - an
application never sets its own `host.name`/`os.type`/etc., only what's
specific to that one application.

## The `app.<service.name>.*` Namespace

[`schema/core.yaml`](../schema/core.yaml)'s
`application_extensions` section is the schema-level home for this;
this directory is where each application's own concrete values (and,
if it ever needs one, its own custom attribute) actually live.

Namespacing every application-specific attribute under
`app.<service.name>.*` prevents collisions between applications - two
apps can each define their own `app.<name>.payment_method` without
stepping on each other, since the key itself embeds which application
it belongs to.

**Illustrative example only** (not a real attribute any demo app
defines today):

```yaml
app.payment-gateway.payment_method: "twint"    # fictional example
app.payment-gateway.processing_stage: "settlement"
```

## Onboarding a New Application

1. Start from [`_template/`](_template/) - copy it to
   `instrumentation/applications/<system-id>-<your-app>/`.
2. Confirm which platform/middleware template(s) it builds on (e.g.
   Java → [`instrumentation/middleware/java/`](../middleware/java/)).
3. Decide whether it needs any `app.<service.name>.*` attribute of its
   own - most applications don't (see the four real entries below, all
   currently Core-Schema-only).
4. Check for naming collisions and cardinality risk against
   [`schema/core.yaml`](../schema/core.yaml)'s Cardinality
   Rule before adding one - see [B10](../../README.md#b10-telemetry-schema).

## This Demo's Applications

| App | System ID | Template | Guide |
|---|---|---|---|
| Mitarbeiterverzeichnis | 4711 | Java/Tomcat | [`4711-mitarbeiterverzeichnis/`](4711-mitarbeiterverzeichnis/) |
| Spesenabrechnung | 4722 | .NET | [`4722-spesenabrechnung/`](4722-spesenabrechnung/) |
| Kundenverwaltung | 4721 | Java (Kubernetes) | [`4721-kundenverwaltung/`](4721-kundenverwaltung/) |
| OTel Astronomy Shop Demo | 4720 | Polyglot (Kubernetes) | [`4720-otel-astronomy-shop/`](4720-otel-astronomy-shop/) |
