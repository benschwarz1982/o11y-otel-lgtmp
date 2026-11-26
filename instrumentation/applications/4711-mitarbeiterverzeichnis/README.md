# Mitarbeiterverzeichnis (4711)

[← Back to the application template index](../README.md)

## Platform/Middleware

Runs on [1286 Linux Basis](../../platforms/1286-linux-basis/) (Apache Tomcat) +
the [Java middleware template](../../middleware/java/) - Tomcat's own
JVM/app-server telemetry reports under this same application tenant,
not a separate middleware one, see [Multi-
Tenancy](../../../README.md#b9-multi-tenancy-onboarding)'s
"Middleware/runtime tenants" note.

## System ID

`4711` - see [Onboarding](../../../README.md#onboarding). Dashboard
template: `applications/tomcat-vm.template.json`.

## Concrete Config

[`instrumentation/middleware/tomcat/`](../../middleware/tomcat/)'s
`tomcat.service.j2` (Java agent env vars, systemd-embedded) +
`collector-config.yaml` (log-file shipping) - both rendered by
`deploy-instrumentations:4711-mitarbeiterverzeichnis`, which passes
this system's `tenant_id`/`service_name`/`service_namespace`/
`app_owner`/`app_cost_center`/`app_size_class`/`deployment_environment`
as Ansible `-e` args (see `.gitlab-ci.yml`). No separate app source -
unlike this repo's other three applications, there is no
custom-written Mitarbeiterverzeichnis code: stock Apache Tomcat with
its own bundled example webapp stands in for the app, and
`ansible/roles/middleware-tomcat/` (above) is the single canonical
implementation of everything that runs on it.

## App-Specific Attributes

None - Core Schema only today.
