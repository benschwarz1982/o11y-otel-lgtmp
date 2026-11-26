# OTel Astronomy Shop Demo (4720)

[← Back to the application template index](../README.md)

## Platform/Middleware

Runs on [Kubernetes](../../platforms/4087-container-platform/) - the official
OpenTelemetry Astronomy Shop Demo chart, ~15 microservices, polyglot
(no single language/middleware template applies - each service is
already OTel-SDK instrumented by the upstream chart).

## System ID

`4720` - see [Onboarding](../../../README.md#onboarding). Dashboard
template: `applications/microservices-k8s.template.json`.

## Concrete Config

[`values-instrument.yaml`](values-instrument.yaml)'s
`default.envOverrides` - layered onto every microservice via the
chart's own mechanism (on top of the base
[`helm/values/otel-demo-values.yaml`](../../../helm/values/otel-demo-values.yaml),
which lives alongside the LGTM stack's own Helm values - that one's
the chart's own config, not instrumentation), carries
`OTEL_EXPORTER_OTLP_HEADERS` (tenant routing) and
`OTEL_RESOURCE_ATTRIBUTES` (this schema's Core Schema attributes).
Read directly by Terraform
(`terraform/environments/fleet-4720-otel-astronomy-shop/main.tf`'s
`file()`).

## App-Specific Attributes

None - Core Schema only today.
