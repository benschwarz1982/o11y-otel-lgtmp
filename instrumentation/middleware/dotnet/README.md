# .NET Middleware Template

For any .NET application, regardless of which platform (Windows,
Linux, Kubernetes, ...) it happens to run on. This is a
middleware/technology template, not a platform template - owned by
application teams, sends under the application's own tenant, never
through the platform's own collector. The tenant is bound server-side
(F03): on a VM via a small local relay collector with the application's
own mTLS client certificate, on Kubernetes via the pod's namespace
(manifest `k8s_namespaces`). A `tenant_id` header is ignored.

## What this is for

Unlike Java's separate `-javaagent` auto-instrumentation jar, this
repo wires OpenTelemetry into .NET applications directly via the SDK
in code - simpler to set up reliably (especially on Windows) than the
separate [.NET auto-instrumentation
bundle](https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation),
and just as complete for a typical ASP.NET Core app. The application
owner adds the OpenTelemetry NuGet packages and a few lines of startup
code once; after that, only environment variables change between
environments/deployments.

## Steps

1. In your app's startup code (`Program.cs` or equivalent), wire up the
   SDK - see [`app/4722-spesenabrechnung/Program.cs`](../../../app/4722-spesenabrechnung/Program.cs)
   in this repo for the full working pattern:
   `AddOpenTelemetry().WithTracing(...).WithMetrics(...)` plus
   `AddAspNetCoreInstrumentation()` for the HTTP layer, `AddOtlpExporter()`
   on both, and `builder.Logging.AddOpenTelemetry(...)` for logs.
2. Set the environment variables from
   [`otel.env.template`](otel.env.template) - fill in
   `<GATEWAY_ENDPOINT>` and `<TENANT_ID>` for your application and
   environment. No local collector relay needed - the SDK pushes
   straight to the gateway.
3. Restart the application. Traces/metrics/logs should appear under
   your application's own tenant within seconds.

## Live in this demo's fleet

4722 Spesenabrechnung (tenant `4722-prod`, `service.name=spesenabrechnung`
set in-app via `Program.cs`'s `ResourceBuilder.AddService(...)`) -
deployed by `deploy-instrumentations:4722-spesenabrechnung`, which
passes this template's values as Ansible `-e` args directly to
`ansible/roles/middleware-dotnet/tasks/instrument.yml`'s
`win_environment` loop (see `.gitlab-ci.yml`) - not through
`otel.env.template` itself, since this app's variables are set as
Windows machine environment variables by Ansible, not read from a
`.env` file. `otel.env.template` stays as the reference for a *new*
.NET app not yet automated this way.

## Continuous Profiling (Pyroscope)

Unlike this template's own OTel SDK wiring (in-code), Pyroscope's .NET
profiler is a native CLR-profiler attach - a standalone downloaded DLL,
activated purely via `CORECLR_ENABLE_PROFILING`/`CORECLR_PROFILER`/
`CORECLR_PROFILER_PATH` environment variables (plus
`PYROSCOPE_PROFILING_ENABLED`/`PYROSCOPE_APPLICATION_NAME`/
`PYROSCOPE_SERVER_ADDRESS`, and `PYROSCOPE_BASIC_AUTH_USER`/
`PYROSCOPE_BASIC_AUTH_PASSWORD` on the service itself) - no NuGet package,
no `Program.cs` change. Pointed at the Pyroscope ingest proxy (it sets
the tenant from the Basic-Auth user), not the gateway (continuous profiling deliberately bypasses
`collector-gateway/otel-gateway-collector.yaml`, see the main README's
B12 section for why). See
`ansible/roles/middleware-dotnet/tasks/instrument.yml` for the worked
example (download + extract + the `CORECLR_*` environment variables).

## Adding `correlation.request_id` (Baggage Schema)

Not part of this template's own env vars - it's application code, not
config. See `app/4722-spesenabrechnung/Program.cs`'s `app.MapPost("/expenses", ...)`
handler for the worked example: generate a request-scoped ID, set it
via `Activity.Current?.AddBaggage(...)` (BCL, W3C-Baggage-compliant),
and explicitly on both the span tag and the log line - neither the
SDK nor the collector copies Baggage onto attributes automatically.
See `instrumentation/schema/core.yaml`'s Baggage Schema section for
the full field reference.
