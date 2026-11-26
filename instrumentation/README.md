# Instrumentation Templates

[← Back to the main README](../README.md) - see
[`B10. Telemetry Schema`](../README.md#b10-telemetry-schema) for the
full write-up. This is the index for a 3-layer model - "where do I
make a change" starts here:

1. **[Schema](schema/)** - the base resource-attribute schema every
   platform/application carries (`service.name`, `deployment.
   environment`, `platform.type`, `app.owner`, ...). One file:
   [`schema/core.yaml`](schema/core.yaml). Global, not
   platform/middleware/application-specific - lives here as this
   layered model's own foundation, not as a fourth layer alongside
   the three below.
2. **Platform/runtime templates** (`platforms/`/`middleware/`) - one
   folder per platform type or middleware technology, each extending
   the base schema with what that platform/runtime actually emits.
3. **[Application templates](applications/)** - one folder per
   application, extending its own platform/runtime template with
   anything specific to that one app.

## Platform Templates

| Platform | Guide | Live in this demo's fleet? |
|---|---|---|
| Linux (RHEL-like) | [`platforms/1286-linux-basis/`](platforms/1286-linux-basis/) | ✅ 1286 Linux Basis |
| Windows Server | [`platforms/1229-windows-basis/`](platforms/1229-windows-basis/) | ✅ 1229 Windows Server Basis |
| Kubernetes / AKS | [`platforms/4087-container-platform/`](platforms/4087-container-platform/) | ✅ this platform's own AKS cluster |
| Network device (SNMP) | [`platforms/1294-netzwerk-basis/`](platforms/1294-netzwerk-basis/) | ✅ 1294 Netzwerk Basis (simplified/simulated) |
| Object storage | [`platforms/object-storage/`](platforms/object-storage/) | ✅ 4015 Filestorage (simplified/simulated) |
| NetApp ONTAP | [`platforms/4015-filestorage/`](platforms/4015-filestorage/) | ⚠️ reference only, not deployed |
| Mainframe z/OS | [`platforms/1285-mainframe-basis/`](platforms/1285-mainframe-basis/) | ⚠️ reference only, not deployed |

Adding a new platform type: start from
[`platforms/_template/`](platforms/_template/).

## Middleware/Runtime Templates

| Technology | Guide |
|---|---|
| Java (JVM) | [`middleware/java/`](middleware/java/) |
| .NET | [`middleware/dotnet/`](middleware/dotnet/) |
| Tomcat (builds on Java) | [`middleware/tomcat/`](middleware/tomcat/) |

Adding a new middleware/runtime technology: start from
[`middleware/_template/`](middleware/_template/).

## Application Templates

See [`applications/README.md`](applications/README.md) for the full
index (4 real demo apps + a blank `_template/` for onboarding a new
one).
