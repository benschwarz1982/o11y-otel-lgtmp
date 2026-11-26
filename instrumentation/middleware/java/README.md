# Java Middleware Template

For any JVM-based application, regardless of which platform (Linux,
Windows, Kubernetes, ...) it happens to run on. This is a
middleware/technology template, not a platform template - owned by
application teams, sends under the application's own tenant, never
through the platform's own collector. The tenant is bound server-side
(F03): on a VM via a small local relay collector with the application's
own mTLS client certificate, on Kubernetes via the pod's namespace
(manifest `k8s_namespaces`). A `tenant_id` header is ignored.

## What this is for

Attaches the [OpenTelemetry Java auto-instrumentation
agent](https://github.com/open-telemetry/opentelemetry-java-instrumentation)
to any JVM process and pushes traces, metrics, and logs **directly to
the OTel gateway** - no local collector relay needed. This means the
application owner never has to touch the underlying platform's
collector config: attaching this agent and setting these environment
variables is the entire integration.

## Steps

1. Download the agent jar (pin the version - this repo currently uses
   `2.34.0`):
   ```bash
   curl -L -o opentelemetry-javaagent.jar \
     "https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.34.0/opentelemetry-javaagent.jar"
   ```
2. Add `-javaagent:/path/to/opentelemetry-javaagent.jar` to the JVM's
   startup command line (before the application's own `-jar`/main
   class argument).
3. Set the environment variables from
   [`otel-java-agent.env.template`](otel-java-agent.env.template) -
   fill in `<SERVICE_NAME>`, `<SERVICE_NAMESPACE>`, `<GATEWAY_ENDPOINT>`,
   `<TENANT_ID>` for your application. Everything else in that file is
   standard and shouldn't need changing.
4. Restart the JVM process. Traces/metrics/logs should appear under
   your application's own tenant within seconds.

## If your app server also writes its own log files

The Java agent only ships logs it can see through the JVM's own
logging framework (`java.util.logging`, wired up via
`OTEL_INSTRUMENTATION_JAVA_UTIL_LOGGING_ENABLED=true` above). If your
app server *also* writes separate log files the JVM itself doesn't
know about (e.g. Tomcat's `catalina.out`/access log), those need a
small dedicated file-shipping collector - see
[`instrumentation/middleware/tomcat/`](../tomcat/) for the concrete, working
example; the same pattern applies to any other file-logging app
server.

## Live in this demo's fleet

No app currently applies `otel-java-agent.env.template` literally as a
file - the two Java apps in this demo's fleet each wire the same
variables through their own deployment mechanism instead:
- **4711 Mitarbeiterverzeichnis** (Tomcat, VM-based): via
  [`instrumentation/middleware/tomcat/`](../tomcat/)'s
  `tomcat.service.j2` (this template's variables set as systemd
  `Environment=` lines instead of a standalone `.env` file, since
  that's where a JVM-under-systemd's env vars actually live) - the
  closest live example of this template's pattern.
- **4721 Kundenverwaltung** (Kubernetes-based): via Terraform `env`
  blocks directly in `terraform/environments/fleet-4139-postgresql/
  main.tf` - a different deployment mechanism entirely (no Ansible
  involved), same variable set.

This template stays as the reference for a *new*, VM-based Java app
not yet automated either way.

## Continuous Profiling (Pyroscope)

Same attach mechanism as the OTel agent above - a second, independent
`-javaagent:` flag (Pyroscope's own agent, `io.pyroscope:agent`), no
code changes. Both jars can be attached at once
(`-javaagent:opentelemetry-javaagent.jar -javaagent:pyroscope-javaagent.jar`).
Configured via `PYROSCOPE_APPLICATION_NAME`/`PYROSCOPE_SERVER_ADDRESS`/
`PYROSCOPE_BASIC_AUTH_USER`/`PYROSCOPE_BASIC_AUTH_PASSWORD` environment
variables, parallel to the `OTEL_*` ones - but pointed at the Pyroscope
ingest proxy, not the gateway. The proxy sets the tenant from the
Basic-Auth user (user = tenant_id, per-tenant password from the Secret
`pyroscope-ingest-<tenant_id>`); `PYROSCOPE_TENANT_ID` is not needed
(continuous profiling deliberately bypasses
`collector-gateway/otel-gateway-collector.yaml`, see the main README's
B12 section for why). See
[`instrumentation/middleware/tomcat/tomcat.service.j2`](../tomcat/tomcat.service.j2)
for the worked example.

## Adding `correlation.request_id` (Baggage Schema)

Not part of this template's own env vars - it's application code, not
config. See `app/4721-kundenverwaltung/Main.java`'s `CustomersHandler.handle()`
for the worked example: generate a request-scoped ID, set it on
`io.opentelemetry.api.baggage.Baggage.current()`, and explicitly on
both the current span attribute and the log line - neither the SDK
nor the collector copies Baggage onto attributes automatically. See
`instrumentation/schema/core.yaml`'s Baggage Schema section for the
full field reference.
