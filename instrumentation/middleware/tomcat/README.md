# Tomcat Middleware Template

Builds on the [Java template](../java/) - use that first for the Java
agent/traces/metrics/JVM-visible-logs part, then add this for Tomcat's
own log **files** (`catalina.out`, the access log), which the Java
agent can't see on its own.

Both files here are the single canonical copies - rendered directly by
`ansible/roles/middleware-tomcat/tasks/{install,instrument}.yml` (no
separate mirror lives under that role anymore):
[`tomcat.service.j2`](tomcat.service.j2) (the systemd unit, with an
`{% if otel_instrumented %}` block attaching the Java agent) and
[`collector-config.yaml`](collector-config.yaml) (the dedicated
log-shipping sidecar collector).

## Steps

1. Follow [`../java/README.md`](../java/README.md) first for the
   general pattern - here, that's `tomcat.service.j2`'s conditional
   `CATALINA_OPTS=-javaagent:...`/`OTEL_*` block instead of a
   standalone env file, since Tomcat's own systemd unit is where those
   variables need to live.
2. Install a **second, independent** `otelcol-contrib` instance (same
   binary as any platform collector, separate systemd service -
   `otelcol-tomcat`) using [`collector-config.yaml`](collector-config.yaml).
   Its only job is tailing Tomcat's log files and shipping them to the
   gateway under the same tenant and service identity
   `tomcat.service.j2` uses - both files take the same Jinja2
   variables (see either file's own header comment), keep them in
   sync.
3. Grant that service read access to Tomcat's log directory:
   ```bash
   sudo usermod -aG tomcat <otelcol-tomcat's service user>
   sudo chmod g+x /opt/tomcat   # default is 700, blocks traversal by group members
   ```
4. `sudo systemctl enable --now otelcol-tomcat`.

## Why a second collector instance, not one shared with the platform?

Keeps this template fully self-contained - the application/middleware
owner installs and owns this collector instance end to end, and never
has to edit the platform team's own collector config
(`instrumentation/platforms/1286-linux-basis/config.yaml`) to add Tomcat-specific
receivers to it. The platform's collector stays identical across every
Linux VM, regardless of what middleware ends up running on top; this
one travels with Tomcat wherever Tomcat gets deployed.

## Continuous Profiling (Pyroscope)

`tomcat.service.j2`'s `{% if otel_instrumented %}` block also attaches
Pyroscope's Java agent (a second `-javaagent:` flag alongside the OTel
one) - see [`../java/README.md`](../java/README.md#continuous-profiling-pyroscope)
for the general pattern. `ansible/roles/middleware-tomcat/tasks/instrument.yml`
downloads both jars the same way.

## Live in this demo's fleet

4711 Mitarbeiterverzeichnis (tenant `4711-prod`) - deployed by
`deploy-instrumentations:4711-mitarbeiterverzeichnis`, which passes
this template's Jinja2 variables as Ansible `-e` args (see
`.gitlab-ci.yml`). `ansible/roles/middleware-tomcat/` is the single
canonical implementation - a hand-runnable `setup-tomcat.sh`/
`instrument-tomcat.sh` reference used to sit alongside it; deleted
once it had already silently drifted from what the role actually
deploys (see README.md's Known Pitfalls), the same "collapse to one
canonical file" principle this template's own config-file merge
already applied.
