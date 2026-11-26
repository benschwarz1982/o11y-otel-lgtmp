# \<Middleware/Runtime Name\> Template

[← Back to the template index](../../README.md) - layer 2 of the
[3-layer model](../../schema/README.md) (schema → **platform/
runtime** → application).

Copy this folder to `instrumentation/middleware/<your-technology>/` when
adding a new middleware/runtime technology (e.g. Python, Go, Node.js).
Follow the shape the other middleware templates already use - see
[`java/`](../java/) (auto-instrumentation agent) or
[`dotnet/`](../dotnet/) (direct SDK wiring) as the two established
patterns, and [`tomcat/`](../tomcat/) for how a technology that
*builds on* another one (Tomcat on Java) is structured.

For any platform (Linux, Windows, Kubernetes, ...) it happens to run
on - this is a middleware/technology template, not a platform
template, same distinction the existing ones already make explicit in
their own opening paragraph. State in the guide:

1. Which OTel mechanism this technology uses (auto-instrumentation
   agent vs. direct SDK wiring vs. something else) and why - a real
   reason, not a default (see `dotnet/README.md`'s own comment for why
   this repo picked direct SDK wiring over the .NET auto-
   instrumentation bundle).
2. The env vars/config template itself, with its own placeholders
   documented (`<TENANT_ID>`, `<SERVICE_NAME>`, and this schema's
   per-tenant attributes - `<DEPLOYMENT_ENVIRONMENT>`/`<APP_OWNER>`/
   `<APP_COST_CENTER>`/`<APP_SIZE_CLASS>`, see
   [`schema/core.yaml`](../../schema/core.yaml)), same
   pattern `java/otel-java-agent.env.template` and
   `dotnet/otel.env.template` already use.
3. Anything this technology needs beyond OTLP (e.g. Tomcat's own log
   *files*, not picked up by the agent on its own).

Update [`instrumentation/README.md`](../../README.md)'s middleware table with
the new entry.
