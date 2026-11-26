# \<Application Name\> - Application Template

[← Back to the application template index](../README.md)

Copy this folder to `instrumentation/applications/<your-app>/` and fill in the
sections below when onboarding a new application.

## Platform/Middleware

Which [platform](../../platforms/) and
[middleware](../../middleware/) template(s) does this application
build on? (e.g. Linux VM + Java middleware, or a Kubernetes pod with
no separate VM platform.)

## System ID

The System ID assigned via [Onboarding](../../../docs/self-service.md#onboarding)
- the manifest is the source of truth for `owner`/`cost_center`/
`environments[].size`, which flow into this app's resource attributes
via the platform/middleware template's own placeholder substitution
(`<APP_OWNER>`/`<APP_COST_CENTER>`/`<APP_SIZE_CLASS>`/
`<DEPLOYMENT_ENVIRONMENT>` - see
[`schema/core.yaml`](../../schema/core.yaml)).

## Concrete Config

Where does this application's actual, filled-in config live? (e.g. an
`OTEL_RESOURCE_ATTRIBUTES` env var in its Helm values, a Terraform
`env` block, an `.env` file rendered from a middleware template.) Link
to it here rather than duplicating it.

## App-Specific Attributes (`app.<service.name>.*`)

Does this application need any attribute beyond the Core Schema? Most
don't - see [`instrumentation/applications/README.md`](../README.md) for the
naming convention and the cardinality check before adding one. If
none: state that explicitly, don't leave this section silently empty.
