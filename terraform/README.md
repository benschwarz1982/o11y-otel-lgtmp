# Terraform

[← Back to the main README](../README.md). Part of the
["Infrastructure & Observability Stack" subsection](../docs/setup.md#b-infrastructure--observability-stack-pipeline)
under [Deployment](../docs/setup.md#deployment).

Structure:

- `modules/aks-cluster/` – AKS cluster (replaces manual `az aks create`) ✅
- `modules/networking/` – client VNet + peering (see main README [B1](../docs/setup.md#b1-apply-aks-cluster--network)) ✅. The AKS VNet/subnet (`aks-vnet`/`aks-subnet`) and the DNS zone are both referenced via `data` sources only, **not** created by Terraform - both are one-time manual bootstrap resources (main README [A5](../docs/setup.md#a5-create-aks-vnet--grant-ci-sp-role-assignment)/[A2](../docs/setup.md#a2-create-dns-zone--cloudflare-ns-delegation)), decoupling their lifecycle from the cluster destroy/apply cycle. `aks-vnet` used to be Terraform-managed too - moved out after finding live, repeatedly, that the CI SP's `User Access Administrator` grant on it doesn't survive a delete+recreate of the VNet even though its resource ID is deterministic, so this dropped a manual step that had to be redone after every full destroy/rebuild cycle down to genuinely zero (see main README [Known Pitfalls](../docs/known-pitfalls.md#known-pitfalls))
- `environments/demo/` – cluster/network, composed from the two modules above; managed **by the GitLab CI pipeline** (`build:terraform-plan`/`deploy:infra`/`destroy:infra` in `.gitlab-ci.yml`) ✅
- `environments/observability-stack/` – LGTM stack, collector RBAC/Service, dashboards, ingress Helm releases (Traefik/cert-manager), Grafana DNS record - `helm_release`/`kubernetes_*` resources ✅ (main README [B2](../docs/setup.md#b2-lgtmp-stack--otel-collectors))
- `environments/observability-stack-crs/` – cert-manager `ClusterIssuer`/`Certificate`/Traefik `IngressRoute` - `kubernetes_manifest` resources reading the same YAML files under `../../k8s/` (`yamldecode(file(...))`, not transcribed to HCL). The **gateway** and **agent** OTel Collector CRs deliberately do NOT live here (their routing is generated from the manifests) - see `environments/tenants/`'s entry below. A **separate Terraform state from `observability-stack`**, applied right after it in the same `deploy:observability-stack` CI job: the `kubernetes` provider needs a CRD's schema to already exist in the live cluster to plan a `kubernetes_manifest` of that kind, and `observability-stack`'s own Helm releases (OTel Operator/cert-manager/Traefik) are what install those CRDs - see that module's `versions.tf` for the full reasoning (this is HashiCorp's own documented pattern for the problem, not a repo-specific workaround) ✅
- `modules/client-vm/` – reusable Linux/Windows VM module (`os_type` variable), creates the VM plus its NIC/Public IP/NSG explicitly with the same naming `az vm create` used to generate automatically ✅ (main README [Fleets](../docs/setup.md#c-fleets-pipeline))
- `environments/fleet-1286-linux-basis/`/`environments/fleet-1229-windows-basis/` – one `client-vm` module call each (linux/windows), each its own state, managed by the `deploy-fleets:1286-linux-basis`/`deploy-fleets:1229-windows-basis` CI jobs ✅
- `environments/fleet-1294-netzwerk-basis/` – SNMP simulator + its dedicated OTel collector sidecar (typed `kubernetes_*` resources, not `kubernetes_manifest` - plain core-API objects, no CRD involved). `var.instrument` (bool) toggles which collector config `ConfigMap` gets deployed, replacing the old `fleet-1294-netzwerk-basis.sh`/`instrumentation-1294-netzwerk-basis.sh` wholesale-swap-and-restart dance - same two-step Runbook choreography, now one Terraform variable ✅
- `environments/fleet-4015-filestorage/` – real `azurerm_storage_account` (deterministic name via a `random_string` kept in state, replacing the old script's fresh-random-every-run name that could only be found again by prefix-scanning at destroy time) + a synthetic Python workload against it. `var.instrument` toggles the workload's `OTEL_EXPORTER_OTLP_ENDPOINT` env var between an inert loopback address and the real gateway - a plain env var change on the Deployment pod template triggers its own rollout, no restart trick needed ✅
- `environments/fleet-4139-postgresql/` – PostgreSQL, Kundenverwaltung's (4721) own dedicated, permanently exclusive database, provisioned in the same environment/state as the application itself, not a separate one: they already share the `kundenverwaltung` namespace, the app already requires the postgres pod `Ready` before it can apply, and the old destroy script already tore down both together - Terraform's own dependency graph (the StatefulSet's built-in wait-for-rollout, an explicit `depends_on`) models this more correctly than a `terraform_remote_state` cross-reference between two states would. The directory/state name is a historical holdover from when PostgreSQL was still onboarded as its own system (4139) - since folded into 4721 as a tenant (see main README's Multi-Tenancy "Middleware/runtime tenants" note); renaming the directory itself was deliberately skipped to avoid migrating a live Terraform state for a purely cosmetic gain. Only `deploy-fleets:4721-kundenverwaltung`/`deploy-instrumentations:4721-kundenverwaltung`/`destroy:4721-kundenverwaltung` apply this environment now - there used to be redundant `*:4139-postgresql` CI jobs applying the exact same state, which had a real footgun while they existed (**found live: since both applied the same `var.instrument`, whichever of the four related jobs ran last won for both systems**) - removed once the redundancy was recognized, see main README [Known Pitfalls](../docs/known-pitfalls.md#known-pitfalls). Also has the one CRD in this milestone that risked the `kubernetes_manifest` provider bug (`postgres-otel-collector.yaml`'s `OpenTelemetryCollector`, `count = var.instrument ? 1 : 0`) - applied cleanly live, bug not hit ✅
- `environments/fleet-4720-otel-astronomy-shop/` – the official OpenTelemetry Astronomy Shop Demo chart via `helm_release` (version pinned - `0.41.0` at implementation time - the old script's `helm upgrade --install` had no `--version` at all), same DNS-A-record/`kubernetes_manifest`-cert/ingressroute ingress pattern as `deploy-fleets:4721-kundenverwaltung`. `var.instrument` layers `values-instrument.yaml`'s `envOverrides` onto the base `values.yaml` in the `helm_release`'s own `values` list, replacing the old two-step `helm upgrade --install` then `--reuse-values` dance ✅
- `environments/tenants/` – every onboarded tenant's own Grafana datasources/dashboards - **4087 (the platform itself) included, no longer special-cased into `environments/observability-stack`'s scope** (its ingestion budget/datasource triplet/dashboard used to be static there; now `datasources/4087-cloud-container-plattform-prod.yaml` and `dashboards/prod/4087-cloud-container-plattform.json` are treated exactly like every other tenant's files, and `helm/values/{mimir,loki}-tenant-overrides.yaml` carries its budget entry) - **and the gateway OTel Collector CR** (`otel-gateway-collector.yaml`, moved here from `observability-stack-crs`), managed by the `tenants:rollout` CI job - a separate state from `observability-stack` on purpose (see this environment's own `main.tf` header comment: `tenants:rollout` needs to stay independently, incrementally runnable on every onboarding merge, without requiring the full platform stack pipeline). That file embeds the onboarding tenant allowlist (`filter/reject_unknown_tenants`), so rolling it out on `tenants:rollout`'s onboarding-approval cadence rather than `deploy:observability-stack`'s platform-only one is what makes the allowlist actually reflect "approved tenants only" - see main README's [Multi-Tenancy](../docs/setup.md#b9-multi-tenancy-onboarding) section. Applied the same way it was in `observability-stack-crs` (`null_resource` + `kubectl apply`, not `kubernetes_manifest` - that CR hits a real, reproduced `hashicorp/kubernetes` provider bug, see main README [Known Pitfalls](../docs/known-pitfalls.md#known-pitfalls)), now reusing this environment's own `local_sensitive_file.kubeconfig`. Datasource files under `datasources/` are already complete `ConfigMap` manifests (auto-generated by `scripts/provision.py`) - decoded with `yamldecode(file(...))` and passed straight through to a typed `kubernetes_config_map`, not transcribed by hand. Dashboards use the same `fileset()` + `for_each` convention as `observability-stack/main.tf`'s own `kubernetes_config_map.dashboards`. The Grafana restart an offboarded tenant's `deleteDatasources` tombstone needs can't be a same-state Deployment-annotation trick (Grafana's Deployment is owned by `observability-stack`'s own state) - same `null_resource` + `kubectl` pattern, hash-triggered on the combined datasources+dashboards content. The Mimir/Loki ingestion-budget `helm upgrade --reuse-values` calls deliberately stay outside Terraform entirely (inlined as plain `script:` lines in the `tenants:rollout` CI job instead) - they layer onto `helm_release.mimir`/`helm_release.loki`, already owned by `observability-stack`'s own state; a second state managing the same Helm release would fight over ownership ✅

The Resource Group itself is **not** created by Terraform, only referenced
via `data "azurerm_resource_group"` (sandbox subscriptions usually
pre-provision it, see main README [Prerequisites](../docs/setup.md#prerequisites)).
The DNS zone and `aks-vnet`/`aks-subnet` (`data` sources in
`modules/networking`) likewise - see above.

**No dedicated Terraform environment for the bootstrap service principals**
(GitLab CI identity, cert-manager identity): they're deliberately created
via a direct, documented `az ad sp create-for-rbac` command instead of a
Terraform module - see main README
[A3](../docs/setup.md#a3-create-the-gitlab-ci-service-principal) and
[A6](../docs/setup.md#a6-create-the-cert-manager-service-principal).
Terraform would only wrap the same `az` command via `local-exec` here,
with no real added value (see main README
[Known Pitfalls](../docs/known-pitfalls.md#known-pitfalls) for background on why the
declarative `azuread_*` resources don't work reliably in this tenant).

## Applying `environments/demo`

**Via the GitLab CI pipeline** (the standard path): `build:terraform-plan`
(stage `build`) runs automatically on every push/MR, `deploy:infra`/
`destroy:infra` (stage `deploy`/`destroy`) are manual jobs. Needs the
CI/CD variables `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (see main README
[A3](../docs/setup.md#a3-create-the-gitlab-ci-service-principal)/[A4](../docs/setup.md#a4-set-gitlab-cicd-variables-azure_))
- these get briefly mapped to `ARM_*` internally, since the `azurerm`
provider only auto-detects that naming convention. Also assumes the DNS
zone and `aks-vnet`/`aks-subnet` already exist (main README
[A2](../docs/setup.md#a2-create-dns-zone--cloudflare-ns-delegation)/[A5](../docs/setup.md#a5-create-aks-vnet--grant-ci-sp-role-assignment)) -
otherwise the `data "azurerm_dns_zone"`/`data "azurerm_virtual_network"`
lookups in `modules/networking` fail.

**Locally** (e.g. for debugging, after `./environments/demo/init.sh`):

```bash
cd environments/demo
terraform plan
terraform apply
```

The `azurerm` provider automatically uses the active `az login` session
from the Cloud Shell (locally), or the `ARM_*` environment variables (in
the pipeline).

## Applying `environments/observability-stack` / `observability-stack-crs`

**Via the GitLab CI pipeline** (the standard path): both are applied by
the single `deploy:observability-stack` job (stage `deploy`, two
sequential `terraform apply`s - `observability-stack` then
`observability-stack-crs`) and torn down by `destroy:observability-stack`
(reverse order). No separate `init.sh`/kubeconfig setup - both modules'
`kubernetes`/`helm` providers authenticate via a
`data "azurerm_kubernetes_cluster"` lookup using the same `ARM_*`
credentials as `environments/demo`, not `az aks get-credentials`. Optional
CI/CD variables `CERT_MANAGER_CLIENT_ID`/`CERT_MANAGER_CLIENT_SECRET` map
to `TF_VAR_cert_manager_client_id`/`TF_VAR_cert_manager_client_secret` -
see main README [A6](../docs/setup.md#a6-create-the-cert-manager-service-principal)
and [section B4](../docs/setup.md#b4-cert-manager-secret--clusterissuer).

**Locally**: same `init.sh` pattern as `environments/demo` (`TF_STATE_NAME`
must be set to `observability-stack`/`observability-stack-crs`
respectively - see below), then `terraform apply` in each directory, in
that order.

## Applying `environments/fleet-1286-linux-basis` / `fleet-1229-windows-basis`

**Via the GitLab CI pipeline**: each is its own independent
`terraform apply`, run by the `deploy-fleets:1286-linux-basis`/
`deploy-fleets:1229-windows-basis` CI jobs (stage `deploy-fleets`) and torn down
by `destroy:1286-linux-basis`/`destroy:1229-windows-basis`
(`terraform destroy`) - see main README
[Fleets](../docs/setup.md#c-fleets-pipeline).
No `az vm create`/kubectl/kubeconfig involved at all - pure `terraform
apply` against Azure, same `ARM_*`-from-`AZURE_*` pattern as every other
Terraform job here.

**Locally**: same `init.sh` pattern (`TF_STATE_NAME` =
`fleet-1286-linux-basis`/`fleet-1229-windows-basis`), then
`terraform apply`.

## Terraform State

State is managed via the **GitLab-managed Terraform state backend** (no
dedicated Azure Storage Account needed) - visible in the project under
**Infrastructure > Terraform states**, one state per environment
(`demo`, `observability-stack`, `observability-stack-crs`,
`fleet-1286-linux-basis`, `fleet-1229-windows-basis`). The backend
type is `http` (each environment's own `backend.tf`); credentials are
only passed at `terraform init -backend-config=...` time, since they
differ depending on context:

- **Locally** (e.g. Azure Cloud Shell): `environments/demo/init.sh` with a
  GitLab Personal Access Token (scope `api`) - copy it into the other two
  environments too (or symlink it), setting `TF_STATE_NAME` accordingly.
- **GitLab CI pipeline**: `$CI_JOB_TOKEN` (automatically available, no
  manual secret needed).
