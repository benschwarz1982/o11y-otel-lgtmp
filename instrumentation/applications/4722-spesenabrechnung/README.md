# Spesenabrechnung (4722)

[← Back to the application template index](../README.md)

## Platform/Middleware

Runs on [1229 Windows Server Basis](../../platforms/1229-windows-basis/) + the
[.NET middleware template](../../middleware/dotnet/).

## System ID

`4722` - see [Onboarding](../../../docs/self-service.md#onboarding). Dashboard
template: `applications/dotnet-vm.template.json`.

## Concrete Config

`ansible/roles/middleware-dotnet/tasks/instrument.yml`'s
`win_environment` loop, set from `tenant_id`/`service_namespace`/
`app_owner`/`app_cost_center`/`app_size_class`/`deployment_environment`
Ansible `-e` args passed by `deploy-instrumentations:4722-
spesenabrechnung` (see `.gitlab-ci.yml`) - not
[`instrumentation/middleware/dotnet/otel.env.template`](../../middleware/dotnet/otel.env.template)
directly, see that template's own README for why. `service.name` is
set in-app via the .NET SDK's own `ResourceBuilder`
(`app/4722-spesenabrechnung/Program.cs`).

## App-Specific Attributes

None - Core Schema only today.
