# Ansible (platform-basis and VM-based middleware/app tiers live)

[← Back to the main README](../README.md) - part of IaC Roadmap
milestone 1. Design decision: classic Ansible over SSH (Linux)/WinRM
(Windows) - a deliberate, explicit exception to this repo's usual
"no SSH/RDP, only `az vm run-command`" rule (see main README
[Fleets](../docs/setup.md#c-fleets-pipeline)),
chosen over `ansible-pull` because that has no clean Windows equivalent.

Structure:

- `roles/platform-linux/` – Rocky/RHEL platform setup, live: installs +
  configures the OTel collector (translates
  `scripts/instrumentation-1286-linux-basis.sh` - see that role's
  `tasks/main.yml` for the 1:1 mapping), rendering
  `instrumentation/platforms/1286-linux-basis/config.yaml` directly via `template:`
  (`{{ role_path }}/../../../instrumentation/...`) - no separate copy
  lives under this role's own `templates/` anymore, that file is the
  single canonical one. Platform-team-owned, no application awareness.
- `roles/platform-windows/` – same for Windows
  (`scripts/instrumentation-1229-windows-basis.sh`), rendering
  `instrumentation/platforms/1229-windows-basis/config.yaml` directly
- `playbooks/onboard-platform-linux.yml`/`onboard-platform-windows.yml`
  – one entry point per role above, run by the
  `instrumentation-1286-linux-basis`/`instrumentation-1229-windows-basis`
  CI jobs respectively. Two separate files, not one playbook with
  `--limit`: found live that Ansible parses/resolves every play's module
  references up front regardless of `--limit`, so a combined file would
  make the Linux job's `ansible-playbook` fail resolving
  `ansible.windows.*` modules it never even runs, just because the
  Windows play's roles are also declared in the same file
- `inventory/generated.ini` – **not committed** (gitignored), written
  fresh by each instrumentation-* job right before running
  `ansible-playbook`: VM IP from `terraform output` (against the
  matching `fleet-1286-linux-basis`/`fleet-1229-windows-basis` state -
  same state `terraform/modules/client-vm` provisioned the VM into),
  SSH key/WinRM password from that same module's own sensitive outputs
  - never written to disk outside this one CI job's ephemeral container
- `playbooks/group_vars/all.yml` – shared vars (pinned OTel Collector/
  Java-agent/Tomcat versions, kept in sync with the rest of the repo).
  Lives under `playbooks/`, not `ansible/` directly - Ansible only
  auto-loads `group_vars/` relative to the playbook or inventory
  directory, found live the hard way ("'otel_collector_version' is
  undefined") when it first lived one level up
- `roles/middleware-tomcat/` – Tomcat/Java app tier (4711
  Mitarbeiterverzeichnis) on `vm-rocky-demo`, the single canonical
  implementation - a hand-runnable `setup-tomcat.sh`/`instrument-
  tomcat.sh` reference used to sit alongside it, deleted once it had
  already silently drifted from what this role actually does (see
  README.md's Known Pitfalls). There's no separate Mitarbeiterverzeichnis
  app source anywhere in this repo either - stock Apache Tomcat with
  its own bundled example webapp stands in for the app. One role, two
  `tags:`-selected task files (`install`/`instrument`) instead of two
  playbooks, so the fleet/instrumentation CI-job split (Runbook
  steps 3/4 - app running with no telemetry, then instrumented) is
  preserved without re-parsing module references across host groups
  (see `roles/platform-linux`'s own comment for why that matters).
  `instrumentation/middleware/tomcat/tomcat.service.j2` (rendered
  directly, no local mirror under this role) is one template for both
  phases (conditional block), not two near-duplicate unit files - same
  for that directory's `collector-config.yaml` (the Tomcat
  log-shipping sidecar).
- `roles/middleware-dotnet/` – .NET app tier (4722 Spesenabrechnung) on
  `vm-windows-demo`, translates `scripts/fleet-4722-spesenabrechnung.sh`/
  `instrumentation-4722-spesenabrechnung.sh` (now deleted, CI-job-only
  scripts - a different history than the Tomcat role above, but the
  same end state: no hand-runnable shell equivalent kept alongside it
  either). Same tagged two-phase structure. Copies
  `app/4722-spesenabrechnung/{Spesenabrechnung.csproj,Program.cs}`
  straight from their canonical location rather than duplicating
  them under this role.
- `roles/otlp_client_cert/` – shared OTLP mTLS client certificate
  lifecycle (`tasks_from: linux` / `windows`), used by all four roles
  above: key + CSR generated on the VM, signed by the tenant's
  cert-manager Issuer, renewed 30 days before expiry, plus the root CA
  that verifies the gateway (F08/F11).
- `playbooks/onboard-middleware-tomcat.yml`/`onboard-middleware-dotnet.yml`
  – one entry point per role above, reusing the same `platform_linux`/
  `platform_windows` inventory groups the platform-basis playbooks
  already target (same hosts, no new inventory groups needed). Run by
  `fleet-4711-mitarbeiterverzeichnis`/`fleet-4722-spesenabrechnung`
  (`--tags install`) and
  `instrumentation-4711-mitarbeiterverzeichnis`/`instrumentation-4722-spesenabrechnung`
  (`--tags instrument`).

WinRM itself isn't enabled by default on a fresh Windows Server image -
`terraform/modules/client-vm`'s `azurerm_virtual_machine_extension.winrm_https_setup`
runs an inline PowerShell script on first boot (WinRM service, Basic
auth, firewall rule for 5986 - no script downloaded at runtime). The
run command `pin-winrm-cert` then creates the HTTPS listener with a
self-signed certificate that has the public IP as SAN, which the CI
jobs pin (F08).
