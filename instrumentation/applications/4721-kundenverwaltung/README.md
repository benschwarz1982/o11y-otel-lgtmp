# Kundenverwaltung (4721)

[← Back to the application template index](../README.md)

## Platform/Middleware

Runs on [Kubernetes](../../platforms/4087-container-platform/) - a plain JDK
`HttpServer` + JDBC app, OTel Java agent for auto-instrumentation. Its
own dedicated PostgreSQL database is provisioned in the same
environment/state and reports under this same tenant, not a separate
platform tenant - see [Multi-
Tenancy](../../../docs/setup.md#b9-multi-tenancy-onboarding)'s
"Middleware/runtime tenants" note.

## System ID

`4721` - see [Onboarding](../../../docs/self-service.md#onboarding). Dashboard
template: `applications/java-k8s.template.json`.

## Concrete Config

Two parts:
- The app itself: Terraform-managed `env` blocks in
  [`terraform/environments/fleet-4139-postgresql/main.tf`](../../../terraform/environments/fleet-4139-postgresql/main.tf)
  (the directory name is a historical holdover, see that file's own
  comment) - `OTEL_RESOURCE_ATTRIBUTES` there carries this system's
  `service.namespace`/`platform.type`/`deployment.environment`/
  `app.owner`/`app.cost_center`/`app.size_class`. App source:
  [`app/4721-kundenverwaltung/Main.java`](../../../app/4721-kundenverwaltung/Main.java)
  (stays under `app/` - that's the app itself, not instrumentation).
- Its dedicated PostgreSQL database's own telemetry (metrics + slow-
  query logs, both reporting under this same tenant):
  [`postgres-otel-collector.yaml`](postgres-otel-collector.yaml)/
  [`postgres-otel-logs-config.yaml`](postgres-otel-logs-config.yaml),
  read directly by the same Terraform file.

## App-Specific Attributes

None - Core Schema only today.
