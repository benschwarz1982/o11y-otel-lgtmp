# Setup and Deployment

One-time bootstrapping and the deployment steps, from an empty resource group to the running platform. The step names (`deploy:infra`, ...) are the GitLab job names - [docs/github-actions.md](github-actions.md#gitlab-job--github-workflow) maps them to the GitHub workflows.

## Prerequisites

- Azure CLI (`az`), logged in (`az login`) - typically via the Azure Cloud
  Shell, since `az`/`kubectl`/`helm`/`terraform` are pre-installed there
- An Azure Resource Group you're allowed to create resources in (usually
  pre-provisioned in sandbox/playground subscriptions - check with
  `az group list --output table`)
- Access to the DNS provider of your parent domain (e.g. Cloudflare for
  `example.com`) to delegate NS records for the subdomain
- For local `terraform init`: GitHub Actions setup - access to the state
  storage account (see [docs/github-actions.md](github-actions.md#local-terraform));
  GitLab setup - a GitLab Personal Access Token (scope `api`) for the
  GitLab-managed state backend


## Deployment

The complete path from an empty Resource Group to a running demo, with **who/what** performs each step - one-time manual bootstrapping, then everything else pipeline-automated.

### A. One-Time Bootstrapping (Manual)

#### A1. Resource Group

Usually already pre-provisioned in sandbox/playground subscriptions -
`az group create` is often not allowed there, so use the existing RG:

```bash
az group list --output table
```

Export it as a shell variable, together with your subscription ID -
every command below that uses `<RESOURCE_GROUP>`/`<SUBSCRIPTION_ID>` means
"substitute `$RESOURCE_GROUP`/`$SUBSCRIPTION_ID` here", not the literal
angle-bracket text (a `Subscription '<SUBSCRIPTION_ID>' not found` error
means exactly that mistake happened):

```bash
export RESOURCE_GROUP=<resource-group>   # from the `az group list` output above
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

These only last for the current shell session - re-export them if you
open a new terminal.

#### A2. Create DNS Zone + Cloudflare NS Delegation

The Azure DNS subdomain zone is deliberately **not** managed by Terraform
(it's only referenced via `data "azurerm_dns_zone"`, see
[`terraform/README.md`](../terraform/README.md)) - this decouples its
lifecycle from the AKS cluster/VNet destroy cycle. Without this
decoupling, every `destroy:infra` + `deploy:infra` cycle would
recreate the zone (new name servers), requiring a fresh, slow NS
delegation at the main DNS provider every single time. Only needed on the
very first setup - the zone stays stable afterwards:

```bash
az network dns zone create -g $RESOURCE_GROUP -n sre.example.com
az network dns zone show -g $RESOURCE_GROUP -n sre.example.com --query nameServers -o tsv
```

At your main DNS provider (e.g. Cloudflare for `example.com`), enter the four
returned name servers as NS records for the subdomain:

| Type | Host | Value |
|---|---|---|
| NS | `sre` | `<ns1-xx.azure-dns.com.>` |
| NS | `sre` | `<ns2-xx.azure-dns.net.>` |
| NS | `sre` | `<ns3-xx.azure-dns.org.>` |
| NS | `sre` | `<ns4-xx.azure-dns.info.>` |

Check the delegation (after ~1 minute, can take up to ~1h):

```bash
dig NS sre.example.com +short
```

#### A3. Create the GitLab CI Service Principal

Always created **by hand**, never by the pipeline (chicken-and-egg
problem: the pipeline can't grant itself the permission it needs to reach
Azure in the first place). Deliberately a simple, directly documented `az`
command instead of its own Terraform module/state - Terraform would only
wrap the same command via `local-exec` here, with no real added value:

```bash
az ad sp create-for-rbac \
  --name "sp-gitlab-ci-observability-otel-demo" \
  --role "Contributor" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
  --query "{client_id: appId, client_secret: password, tenant_id: tenant}" \
  -o json
```

#### A4. Set GitLab CI/CD Variables (`AZURE_*`)

From the A3 output (Settings → CI/CD → Variables in GitLab):

| Field from the `az` output | GitLab variable | Flags |
|---|---|---|
| `client_id` | `AZURE_CLIENT_ID` | - |
| `client_secret` | `AZURE_CLIENT_SECRET` | masked, protected |
| `tenant_id` | `AZURE_TENANT_ID` | - |
| (your subscription ID, `echo $SUBSCRIPTION_ID`) | `AZURE_SUBSCRIPTION_ID` | - |
| (your resource group) | `AZURE_RESOURCE_GROUP` | - |
| (the DNS zone from A2, e.g. `sre.example.com`) | `DNS_ZONE` | - |
| (optional, Let's Encrypt contact) | `ACME_EMAIL` | - |

> The `build:terraform-plan`/`deploy:infra`/`destroy:infra` jobs in
> `.gitlab-ci.yml` briefly map these `AZURE_*` variables to `ARM_*`
> internally, since the `azurerm`/`azuread` Terraform provider only
> auto-detects credentials via that HashiCorp-specific naming convention.

This lets the pipeline authenticate against Azure on its own from now on
(those Terraform jobs, as well as `az aks get-credentials` in every
`deploy:*`/`destroy:*` job).

#### A5. Create aks-vnet + Grant CI SP Role Assignment

`aks-vnet` (and its `aks-subnet`) is deliberately **not** created by
Terraform (only referenced, via `data "azurerm_virtual_network"`/`data
"azurerm_subnet"` in `terraform/modules/networking`) - same decoupling
reason as the DNS zone in [A2](#a2-create-dns-zone--cloudflare-ns-delegation)
above, one step further: the CI SP needs `User Access Administrator`
scoped to this exact VNet before Terraform's own
`azurerm_role_assignment.aks_identity_network_contributor`
(`terraform/modules/aks-cluster/main.tf`) can
succeed - `Contributor` alone (from A3 above) isn't enough to *grant*
roles, only to manage resources directly. An earlier version of this
setup created `aks-vnet` via Terraform, as part of the same
`deploy:infra` apply that (re)creates the AKS cluster - **found live,
repeatedly, across several full destroy+rebuild cycles**: even though
`aks-vnet`'s resource ID is deterministic by name, the role assignment
scoped to it does **not** survive the VNet itself being deleted and
recreated - Azure does not carry a scope's role assignments across a
delete+recreate of the resource at that scope, deterministic ID or not.
So despite this step's grant being logically "one-time", it silently
had to be redone by hand after every `destroy:infra` + `deploy:infra`
cycle. Fixed by moving the VNet itself out of Terraform's
destroy/rebuild cycle - genuinely one-time now, only needed again if
`aks-vnet` is ever deleted by hand.

```bash
az network vnet create -g $RESOURCE_GROUP -n aks-vnet \
  --address-prefix 10.0.0.0/16 \
  --subnet-name aks-subnet --subnet-prefix 10.0.1.0/24

az role assignment create \
  --assignee-object-id "$(az ad sp list --display-name sp-gitlab-ci-observability-otel-demo --query '[0].id' -o tsv)" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope "$(az network vnet show -g $RESOURCE_GROUP -n aks-vnet --query id -o tsv)"
```

#### A6. Create the cert-manager Service Principal

A dedicated service principal for the Azure DNS-01 challenge, scoped to
the DNS zone from [A2](#a2-create-dns-zone--cloudflare-ns-delegation) -
a direct `az` command for the same reason as
[A3](#a3-create-the-gitlab-ci-service-principal), no Terraform wrapper
needed. Since the zone is now a stable, one-time bootstrap building block
(instead of being recreated on every cluster rebuild), this step only
needs to run once as well - no longer on every cluster rebuild:

```bash
ZONE_ID=$(az network dns zone show -g $RESOURCE_GROUP -n sre.example.com --query id -o tsv)

az ad sp create-for-rbac \
  --name "sp-cert-manager-otel-demo" \
  --role "DNS Zone Contributor" \
  --scopes "$ZONE_ID" \
  --query "{client_id: appId, client_secret: password, tenant_id: tenant}" \
  -o json
```

From the output, set the GitLab CI/CD variables (Settings → CI/CD →
Variables) - just like in
[A4](#a4-set-gitlab-cicd-variables-azure_):

| Field from the `az` output | GitLab variable | Flags |
|---|---|---|
| `client_id` | `CERT_MANAGER_CLIENT_ID` | - |
| `client_secret` | `CERT_MANAGER_CLIENT_SECRET` | masked, protected |

This means **no** hardcoded value lives in `cluster-issuer-azuredns.yaml`
anymore that could drift out of sync on a rotation (that's exactly what
happened to us once - `client_id`/`client_secret` fell out of sync, and
cert-manager failed with `AADSTS7000215: Invalid client secret provided`).
The Kubernetes secret and the `ClusterIssuer` itself are now created by
the `deploy:observability-stack` job
([B4](#b4-cert-manager-secret--clusterissuer)).

#### A7. Claude Subscription Setup-Token + OpenClaw Gateway Token

Needed for OpenClaw ([B13](#b13-openclaw-aiops-remediation-ai-ops-azure-integration)).
OpenClaw uses its built-in `anthropic` provider, authenticated with a
**Claude Pro/Max subscription setup-token** instead of a pay-per-token
API key - usage comes out of the subscription's own allowance, no
separate API billing and no Azure resource to provision (same approach
as the `openclaw-app` reference project). Generate the token **on your
own machine**, where Claude Code is installed and logged into the
subscription - not inside the cluster:

```bash
npm install -g @anthropic-ai/claude-code   # if not already installed
claude login                                # log into the claude.ai subscription, if not already
claude setup-token                          # prints the token to stdout
```

It reaches OpenClaw as the `ANTHROPIC_OAUTH_TOKEN` env var (from the
`openclaw-secrets` Secret), nothing is persisted on the PVC. The token
expires after one year: run `claude setup-token` again, update
`ANTHROPIC_SETUP_TOKEN` and re-run `deploy-aiops:aiops` (the Pod rolls
automatically, its template carries a checksum of the token). `openclaw
models status` inside the Pod shows `effective=env:OAuth` for
`anthropic` once it is picked up.

`OPENCLAW_GATEWAY_TOKEN` and `OPENCLAW_HOOKS_TOKEN` have no external
source to copy from - any random string works for each, e.g. `openssl
rand -hex 32` (use a different value for each - they gate two
independent endpoints, see B13's "Trigger" note on why the webhook
uses its own dedicated token rather than reusing the gateway one).
Each is a single CI/CD variable read by every Terraform state that
needs it (`OPENCLAW_HOOKS_TOKEN`: `aiops` for OpenClaw and
`observability-stack` for Grafana's webhook contact point). Neither
token is ever rendered into a ConfigMap: OpenClaw gets both as
environment variables from the Secret `openclaw-secrets`
(`openclaw.json` only holds `${OPENCLAW_HOOKS_TOKEN}`), Grafana reads
the hook token from a file the Secrets Store CSI driver mounts from the
platform Key Vault (`$__file{}` in `alerting/shared/openclaw-webhook.yaml`,
G12 - see [Secrets](platform-features.md#secrets-key-vault-g12-nfr-03)). **Rotating
`OPENCLAW_HOOKS_TOKEN`**: change the CI/CD variable, then run
`deploy-aiops:aiops` and `deploy:observability-stack` - checksum annotations
restart OpenClaw and Grafana with the new value.

`OPENCLAW_MODEL` and `AGENT_NAME`/`ORGANISATION_NAME`/`OPERATOR_NAME`
are all **optional** - each has a working default already baked into
`terraform/environments/aiops/variables.tf` (`openclaw_model`/
`openclaw_agent_name`/`openclaw_organisation_name`/
`openclaw_operator_name`), only used to override those defaults when
actually set. `OPENCLAW_MODEL` is `<provider>/<model id>` from the
OpenClaw image's own catalog (default `anthropic/claude-sonnet-5`, list
the alternatives with `openclaw models list --all --provider
anthropic`); the other three are purely cosmetic identity strings
injected into OpenClaw's own workspace files
(`openclaw/workspace-templates/{AGENTS,IDENTITY,USER}.md`).

Set the GitLab CI/CD variables (Settings → CI/CD → Variables):

| Value | GitLab variable | Flags |
|---|---|---|
| setup-token from `claude setup-token` | `ANTHROPIC_SETUP_TOKEN` | masked, protected |
| any random string (e.g. `openssl rand -hex 32`) | `OPENCLAW_GATEWAY_TOKEN` | masked, protected |
| any random string, different from the above (e.g. `openssl rand -hex 32`) | `OPENCLAW_HOOKS_TOKEN` | masked, protected |
| Model (optional, only if not the default) | `OPENCLAW_MODEL` | - |
| Agent display name (optional, e.g. `Claw`) | `AGENT_NAME` | - |
| Organisation name (optional) | `ORGANISATION_NAME` | - |
| Primary operator name (optional) | `OPERATOR_NAME` | - |

### B. Infrastructure & Observability Stack (Pipeline)

#### B1. Apply AKS Cluster + Network

Runs via the `build`/`deploy`/`destroy` stages in `.gitlab-ci.yml`:

- **`build:terraform-plan`**: runs automatically on every push to `main`
  that touches `terraform/` (no `merge_request_event` rule - this repo
  has no workflow that opens an MR touching `terraform/`, see Known
  Pitfalls)
- **`deploy:infra`**: manual job in the pipeline (CI/CD → Pipelines → ▶️)
- **`destroy:infra`**: manual job, additionally gated behind the
  CI/CD variable `CONFIRM_DESTROY=yes` as a safety net

Only manages the AKS cluster + the `observability-clients-vnet` (plus
peerings) - the DNS zone and `aks-vnet` are both deliberately **not**
part of it (see [A2](#a2-create-dns-zone--cloudflare-ns-delegation) and
[A5](#a5-create-aks-vnet--grant-ci-sp-role-assignment)), so
`destroy:infra`/`deploy:infra` cycles never touch either. Details on
modules, the state backend, and local debugging in
[`terraform/README.md`](../terraform/README.md).

#### B2. LGTM+P Stack + OTel Collectors

Runs via the `deploy:observability-stack` job (stage `deploy` in
`.gitlab-ci.yml`, started manually): two sequential `terraform apply`s,
[`terraform/environments/observability-stack`](../terraform/README.md)
(namespaces, storage account, Loki/Tempo/Mimir/Grafana/Pyroscope/OTel Operator
`helm_release`s, dashboard `kubernetes_config_map`s, collector RBAC) then
[`observability-stack-crs`](../terraform/README.md) (cert-manager issuers
and certificates, Linkerd trust anchor - a separate Terraform state
applied second, since the CRDs the first module installs must already
exist in the cluster before this one can even be planned). Both
collector CRs - **gateway** and **agent** - are applied by
`tenants:rollout` instead, since their routing is generated from the
manifests (see [B6](#b6-per-tenant-datasourcesdashboards)). Authenticates
both modules' `kubernetes`/`helm` providers via
an `azurerm_kubernetes_cluster` data source (the same `AZURE_*` variables
from [A4](#a4-set-gitlab-cicd-variables-azure_), mapped to `ARM_*`) - no
`az aks get-credentials`/kubeconfig involved.

Check rollout status afterwards:

```bash
kubectl get pods -n observability
kubectl get pods -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator
```

All pods should be `Running`. Mimir components (ingester, distributor,
querier) may restart 1-3x on first startup (Kafka bootstrap timing) -
that's harmless as long as they stay stably `Running` afterwards.
Optional troubleshooting for the collectors:

```bash
kubectl logs -n observability -l app.kubernetes.io/component=opentelemetry-collector -c otc-container --tail=30
```

The `destroy:observability-stack` job (stage `destroy`) tears B2 back down
in reverse (`terraform destroy` in `observability-stack-crs` first, then
`observability-stack` - Helm releases + the `observability`/
`opentelemetry-operator-system` namespaces), also gated behind
`CONFIRM_DESTROY=yes`.

#### B3. Install Traefik + cert-manager

Runs as part of the `deploy:observability-stack` job
(`terraform/environments/observability-stack`'s `traefik`/`cert_manager`
`helm_release`s) - no separate manual step needed anymore. The
`destroy:observability-stack` job tears both back down symmetrically.

#### B4. cert-manager Secret + ClusterIssuer

Runs as part of the `deploy:observability-stack` job: `observability-stack`
creates the `azuredns-config` `kubernetes_secret`, `observability-stack-crs`
applies `cluster-issuer-azuredns.yaml` as a `kubernetes_manifest` with its
placeholders (`clientID`, `subscriptionID`, `tenantID`,
`resourceGroupName` - Terraform `templatefile()` syntax, not `sed`)
filled in from the `cert_manager_client_id` Terraform variable and an
`azurerm_client_config` data source. If `CERT_MANAGER_CLIENT_ID`/
`CERT_MANAGER_CLIENT_SECRET` aren't set yet (e.g. because
[A6](#a6-create-the-cert-manager-service-principal) hasn't run yet), both
modules skip this part entirely (`count = var.cert_manager_client_id !=
"" ? 1 : 0`) - the rest of the `deploy:observability-stack` job still
runs through.

Check the status afterwards:

```bash
kubectl get clusterissuer letsencrypt-azuredns
```

Should show `READY=True` (~60-90s after the deploy).

#### B5. Grafana Ingress + Datasources

Runs automatically as part of the `deploy:observability-stack` job:
`observability-stack`'s `grafana` `helm_release` sets `root_url` + the
one genuinely platform-scoped datasource (`Mimir-anonymous`, the
collector/operator self-monitoring data, via
[`helm/values/grafana-values.yaml`](../helm/values/grafana-values.yaml)),
its `azurerm_dns_a_record.grafana` resource creates the `grafana` DNS A
record, and `observability-stack-crs` applies the `Certificate`/
`IngressRoute` `kubernetes_manifest`s. No more error-prone `--set` with
`grafana\.ini` escaping - `root_url` and that datasource are real
YAML keys in the values file, so they're set correctly from the very
first deploy. Every onboarded tenant's own datasources/dashboards -
**4087 (the platform itself) included, no exceptions** - are
deliberately **not** part of this job, only of onboarding/approval -
see [B6. Per-Tenant
Datasources/Dashboards](#b6-per-tenant-datasourcesdashboards)
below.

Prerequisite for the ingress part (DNS record, Certificate, IngressRoute):
[B4](#b4-cert-manager-secret--clusterissuer) must have run
(`CERT_MANAGER_CLIENT_ID`/`CERT_MANAGER_CLIENT_SECRET` set) - otherwise
both Terraform modules skip this part entirely, and Grafana stays
reachable only via port-forward (see below). The DNS record resource
waits a fixed 60s (`time_sleep`) for Traefik's LoadBalancer IP before
reading it - if that's not enough, the apply fails and a re-run picks it
up (unlike the old script's 5-minute retry loop, see [Known
Pitfalls](known-pitfalls.md#known-pitfalls)).

Grafana is then directly and securely reachable at
`https://grafana.sre.example.com`. By default the admin password is
auto-generated by the chart - get it with:

```bash
kubectl get secret grafana -n observability -o jsonpath='{.data.admin-password}' | base64 -d
```

Login: `admin` / `<password>`

To use a known password instead (e.g. to skip the `kubectl` lookup
above on every fresh deploy), set the optional GitLab CI/CD variable
`GRAFANA_ADMIN_PASSWORD` (masked, protected) - `helm_release.grafana`'s
`grafana_admin_password` Terraform variable only overrides the chart's
own `adminPassword` when non-empty, so leaving it unset preserves
today's auto-generated-password behavior exactly.

> **Local access without ingress** (e.g. for quick troubleshooting, or
> while B4 hasn't run yet):
> ```bash
> kubectl port-forward svc/grafana 3000:80 -n observability
> ```
> Then in your browser: `http://localhost:3000`

Check the datasources status: **Connections > Data Sources** - Mimir
(Prometheus), Loki, Tempo should be present automatically, with no manual
clicks needed.

#### B6. Per-Tenant Datasources/Dashboards

Onboarding-scoped, deliberately separate from `deploy:observability-stack`
([B5](#b5-grafana-ingress--datasources)) - the `tenants:rollout`
job (Terraform: `terraform/environments/tenants`, plus a plain `helm
upgrade` step for the Mimir/Loki budgets) applies every onboarded
tenant's own Mimir/Loki/Tempo datasource triplet
(`datasources/<tenant_id>.yaml`, one ConfigMap per tenant,
auto-discovered by Grafana's `sidecar.datasources` - see
`helm/values/grafana-values.yaml`) and dashboard
(`dashboards/<system_id>-<slug>.json`, one flat file per system - 4087's
own dashboard included, no longer excluded/special-cased into
`deploy:observability-stack`'s scope), **and rolls out the gateway
`OpenTelemetryCollector` CR**
(`collector-gateway/otel-gateway-collector.yaml`, moved here from
`deploy:observability-stack`'s scope) - see
[Multi-Tenancy](#b9-multi-tenancy-onboarding) for why that CR's tenant
allowlist belongs on this job's onboarding-approval cadence, not
`deploy:observability-stack`'s platform-only one. All three are
generated and committed by `scripts/provision.py` on every manifest
merge - see [Per-System Dashboards
(Onboarding)](#b8-per-system-dashboards-onboarding) below. Runs in the
SAME pipeline as `tenants:apply` (`needs:` + a matching `changes:`
rule, not a second commit-triggered pipeline - see
[Processes](self-service.md#processes)) - no manual click
needed, confirmed live.

Verified live: a datasource ConfigMap appears in Grafana's own
`/api/datasources` within seconds of `kubectl apply`, no restart
needed, and querying through it correctly returns that tenant's data
(or an empty result if the tenant has no fleet deployed yet) - same
mechanism dashboards already used, just newly applied to datasources
too.

#### B7. Dashboards

Same platform-scoped/onboarding-scoped split as the datasources
([B5](#b5-grafana-ingress--datasources)/
[B6](#b6-per-tenant-datasourcesdashboards)): `deploy:observability-stack`'s
`kubernetes_config_map.dashboards` (Terraform:
`terraform/environments/observability-stack`) covers only the
tenant-agnostic ones under `dashboards/shared/` (operator
budget, collector self-monitoring); `tenants:rollout`'s
`kubernetes_config_map.tenant_dashboards` (Terraform:
`terraform/environments/tenants`) covers every onboarded tenant's own
dashboard, one flat file per system directly under `dashboards/`,
4087's included - no longer special-cased. Both apply each dashboard's
JSON as a ConfigMap labeled `grafana_dashboard=1`; Grafana's dashboard
sidecar (`helm/values/grafana-values.yaml`) watches for these and
imports/updates them automatically - no manual **Dashboards > Import**
clicks needed. The Grafana folder each dashboard lands in is a single
level, just `<system_id>` (e.g. `1286`), computed from each ConfigMap's
`grafana_folder` annotation (the leading `<system_id>-` token of the
filename) - deliberately not nested under an environment folder: a
system's dashboard covers every environment it's onboarded into at
once (an in-dashboard `env` variable switches between them, see
[B8](#b8-per-system-dashboards-onboarding)), and Grafana's dashboard
file-provisioner (`foldersFromFilesStructure`) turns out to only
reliably support one folder level from its mount root anyway -
confirmed live, and a known, open upstream limitation
([grafana/grafana#107158](https://github.com/grafana/grafana/issues/107158)).
`shared/` stays a flat, top-level Grafana folder alongside every
`<system_id>` one - tenant-agnostic, there's no single system_id to
fold it under. `templates/` is the generator's input, not a dashboard,
and is excluded by both. To add another dashboard, drop its JSON export
directly under `dashboards/` and redeploy.

| Dashboard | Grafana folder | Source | Datasource | Note |
|---|---|---|---|---|
| `shared/otel-collector-15983.json` | shared | [grafana.com #15983](https://grafana.com/grafana/dashboards/15983/), revision 30, vendored as-is | Mimir-anonymous (its `$datasource` variable is regex-restricted to this one - see [Known Pitfalls](known-pitfalls.md#known-pitfalls)) | Collector self-monitoring: receiver/processor/exporter throughput, refused/failed items, process health |
| `shared/operator-tenant-budget.json` | shared | hand-authored for this repo | Mimir-anonymous | Cross-tenant operator view: every tenant's daily ingestion budget usage over time, plus per-signal rate-vs-limit and discard panels - see [Multi-Tenancy](#b9-multi-tenancy-onboarding) |
| `4087-cloud-container-plattform.json` | 4087 | generated from `platform-container.template.json` | Mimir + Loki + Tempo (tenant, env-selectable), Mimir-anonymous | Cloud Container Plattform - see [Per-System Dashboards](#b8-per-system-dashboards-onboarding) for what makes this one different |
| `1286-linux-basis.json` | 1286 | generated from `linux-host.template.json` | Mimir + Loki (tenant, env-selectable), Mimir-anonymous | Linux Basis |
| `1229-windows-server-basis.json` | 1229 | generated from `windows-host.template.json` | Mimir + Loki (tenant, env-selectable), Mimir-anonymous | Windows Server Basis (Demo Use Case 2: Windows Service Crash) |
| `1294-netzwerk-basis.json` | 1294 | generated from `network-device.template.json` | Mimir + Loki (tenant, env-selectable), Mimir-anonymous | Netzwerk Basis |
| `4015-filestorage.json` | 4015 | generated from `object-storage.template.json` | Mimir + Loki + Tempo (tenant, env-selectable), Mimir-anonymous | Filestorage |
| `4711-mitarbeiterverzeichnis.json` | 4711 | generated from `tomcat-vm.template.json` | Mimir + Loki + Tempo (tenant, env-selectable), Mimir-anonymous | Mitarbeiterverzeichnis - UC4's own demo tenant, not a Use Case of its own (see Demo Use Cases), JVM/Tomcat panels included, see that template's own note |
| `4722-spesenabrechnung.json` | 4722 | generated from `dotnet-vm.template.json` | Mimir + Loki + Tempo (tenant, env-selectable), Mimir-anonymous | Spesenabrechnung - no longer anchors a Use Case of its own (see Demo Use Cases) |
| `4720-otel-astronomy-shop-demo.json` | 4720 | generated from `microservices-k8s.template.json` | Mimir + Loki + Tempo (tenant, env-selectable), Mimir-anonymous | OTel Astronomy Shop Demo (Demo Use Case 3) |
| `4721-kundenverwaltung.json` | 4721 | generated from `java-k8s.template.json` | Mimir + Loki + Tempo (tenant, env-selectable), Mimir-anonymous | Kundenverwaltung - no longer anchors a Use Case of its own (see Demo Use Cases), JVM runtime panels included, see that template's own note |

> Classic Kubernetes cluster dashboards (node_exporter naming scheme) do
> NOT fit this setup, since OTel hostmetrics/kubeletstats use different
> metric names (`system_*`/`k8s_*` instead of `node_*`/`container_*`) -
> that's why the cluster-health panels on
> `4087-cloud-container-plattform.json` are hand-authored against
> our actual metric names rather than imported from grafana.com, see
> [Known Pitfalls](known-pitfalls.md#known-pitfalls). Deploy `kube-state-metrics`
> separately if you need classic K8s dashboards anyway.

The Tempo service graph needs no dashboard - it works automatically via
Explore > Tempo > Service Graph, since `metricsGenerator` is active with
`service-graphs`/`span-metrics` (data lands in Mimir).

#### B8. Per-System Dashboards (Onboarding)

Every onboarded system gets its own dashboard, stamped from a template
picked via the manifest's **required** `dashboard_template` field (see
[the schema](../manifests/schema.json)) - required, not defaulted or
inferred, since a Kubernetes pod, a VM, and an SNMP device don't share
a label vocabulary and there's no reliable signal to tell them apart
otherwise (found live: leaving it optional silently defaulted every
system to the Kubernetes-pod template regardless of fit).
`scripts/generate-system-dashboard.py` only renders a given template;
this repo owns the template catalog, onboarding data (which template,
per system) lives in `manifests/`.

| Template | Used by | Shape |
|---|---|---|
| `applications/k8s-app.template.json` | (unused) | Kubernetes pod: active series, traces, logs by `k8s_namespace_name` |
| `platforms/platform-container.template.json` | 4087 | AKS cluster itself: node/pod health, ingest/refused rate, PVC usage, platform-wide tenant budget view |
| `platforms/linux-host.template.json` | 1286 | Linux VM (`hostmetrics`): CPU/memory/filesystem/disk I/O by `host_name`, OS release pie, `$host` variable, no traces |
| `platforms/windows-host.template.json` | 1229 | Windows VM (`windowsperfcounters`): same shape, Windows metric vocabulary and WMI-based OS release; 2 Event Log level panels (Error is UC2's alert target) |
| `platforms/network-device.template.json` | 1294 | SNMP device: traffic/error rate by interface, no traces |
| `platforms/object-storage.template.json` | 4015 | Object storage: operations rate/throughput/avg size, storage used + daily growth |
| `middleware/postgresql.template.json` | (unused - see B9's "Middleware/runtime tenants") | PostgreSQL: connections, transactions, cache hit ratio, table size, no traces |
| `applications/microservices-k8s.template.json` | 4720 | K8s demo app: request rate/latency by endpoint (Tempo span metrics), `__DEMO_NARRATIVE__` blurb linking related platform dashboards |
| `applications/java-k8s.template.json` | 4721 | Same as `microservices-k8s` + JVM runtime panels (merged in from a since-retired standalone JVM dashboard) |
| `applications/dotnet-vm.template.json` | 4722 | Same as `microservices-k8s` but VM-based |
| `applications/tomcat-vm.template.json` | 4711 | Same as `dotnet-vm` + JVM/app-server panels (merged in the same way) |

`linux-host`/`windows-host` carry a `$host` variable for fleet-scale
readability. `microservices-k8s`/`dotnet-vm`'s Request Rate/Latency
panels come from Tempo's `metricsGenerator` span metrics automatically
- no extra app instrumentation. Recent Traces is a `table` panel, not
Grafana's `traces` type - see [Known Pitfalls](known-pitfalls.md#known-pitfalls).

```bash
python3 scripts/generate-system-dashboard.py \
  --manifest manifests/platforms/4087-cloud-container-plattform.yaml
```

Writes `dashboards/<system_id>-<slug-of-name>.json` - one file/folder
per system regardless of environment count. Applied by
`deploy:observability-stack` for `shared/` dashboards,
`tenants:rollout` for every tenant's own (4087 included). Wired into
onboarding: `tenants:apply` runs this on every manifest merge and
commits the result - see [Processes](self-service.md#processes).

Each dashboard also needs its own per-environment Mimir/Loki/Tempo
datasources, pinned to that `<system_id>-<env>` tenant -
`scripts/provision.py` (`update_grafana_datasources()`) writes a
`datasources/<tenant_id>.yaml` ConfigMap per tenant, applied by
`tenants:rollout` (see [B6](#b6-per-tenant-datasourcesdashboards)). An
`env` template variable switches the whole dashboard's datasource with
one dropdown instead of a separate file per environment.

Each dashboard's "Configured Ingestion Budget" panel is static text
from the manifest at generation time, not a live query - live
cross-tenant consumption would need Mimir's tenant federation, which
has [known reports of destabilizing the
store-gateway](https://github.com/grafana/mimir/discussions/9989), a
disproportionate risk for one panel per dashboard. Live consumption
instead lives on the Operator dashboard and each tenant's own
"Ingestion Budget Usage" panel - see [B9](#b9-multi-tenancy-onboarding)
for that mechanism.

#### B9. Multi-Tenancy (Onboarding)

Mimir, Loki, and Tempo isolate data per `X-Scope-OrgID`, driven by the
onboarding process's `<system_id>-<env>` tenant convention - see
[`manifests/schema.json`](../manifests/schema.json) for the manifest
schema (`type: platform` = fleet-wide view, `type: application` = a
single app, optionally referencing one or more platforms via
`platform_refs`) and [Processes](self-service.md#processes) for the
full request/approval flow. See [B10](#b10-telemetry-schema) for the
separate, complementary question of what shape a signal's own resource
attributes carry, regardless of which tenant it lands in. Mechanics on
this side:

- **Who decides the tenant (F02/F03)**: never the sending workload.
  Mimir, Loki, Tempo and Pyroscope trust `X-Scope-OrgID` without any
  authentication, so they are only reachable from inside the
  `observability` namespace (NetworkPolicy `observability-backends-ingress`,
  `terraform/environments/observability-stack`), and every write path
  binds the tenant server-side:

  | Sender | Path | Tenant bound by |
  |---|---|---|
  | VM platform collectors (1229, 1286) | Traefik `traefik-otlp-internal:14317` -> gateway receiver `otlp/tenant-<id>` | mTLS client certificate from that tenant's own CA |
  | VM applications (4711 Tomcat, 4722 .NET) | local relay collector (`otelcol-tomcat` / `otelcol-app`, `127.0.0.1:4317`) -> same mTLS path | the application's own mTLS client certificate |
  | Pods in a tenant namespace (4720, 4721, 4015, 1294) | gateway `otlp` 4317/4318 | the pod's namespace (manifest `k8s_namespaces`), looked up from the connection's source IP (`k8sattributes/source` + `routing/*` connectors) |
  | Platform collectors in `observability` (otel-agent) | gateway `otlp` | `tenant_id` header + allowlist below - the only trusted sender, it fans node/pod logs out to many tenants |
  | Profiles (Pyroscope) from VMs and pods | Pyroscope ingest proxy (`pyroscope-internal` LB / `pyroscope-ingest` Service) | Basic Auth, user = tenant_id, per-tenant password (Secret `pyroscope-ingest-<tenant_id>`) |

  Telemetry from any other namespace, or from outside the cluster on
  the plain OTLP ports, is dropped (`<signal>/unattributed`). The
  gateway's `syslog` receiver (5514, not exposed on any Service, no
  sender in this repo) carries no client connection info, so it always
  ends up there too - as before, when it was dropped for lacking a
  `tenant_id`. The gateway's plain OTLP ports bypass linkerd's inbound proxy
  (`config.linkerd.io/skip-inbound-ports`) - through the proxy, every
  connection appeared to come from the gateway itself. The internal
  plain-OTLP LoadBalancer `otel-gateway-internal` was removed.
  Residual risks: VM -> Pyroscope proxy is plain HTTP inside the VNet,
  and the Pyroscope password sits in the VM's service environment.
- **mTLS certificate lifecycle (F08/F11)**: the VM collectors verify the
  gateway's server certificate against the internal root CA (`ca_file`,
  installed by `ansible/roles/otlp_client_cert`) under the SNI name
  `<tenant_id>.otlp.internal` - the server certificate covers it via
  `*.otlp.internal` (`terraform/environments/observability-stack-crs`).
  Client certificates are issued for 90 days and renewed once fewer than
  30 remain - checked on every `deploy-instrumentations:*` run (no
  scheduled renewal, it's a demo: rerun the job before a certificate
  expires). Each run checks expiry and key/certificate match,
  reissues via a fresh key + CSR (the key never leaves the VM) and
  restarts only the collector whose certificate or CA changed. The
  gateway re-reads its own server certificate and the tenant CAs every
  hour (`reload_interval`, `client_ca_file_reload`), so cert-manager's
  renewals take effect without a restart. The tenant intermediates keep
  their key on renewal (`rotationPolicy: Never`) - otherwise the reloaded
  CA would instantly reject every VM certificate it signed. Rotating an
  intermediate's key deliberately: delete its Secret
  `otlp-intermediate-ca-cert-<tenant_id>` (cert-manager reissues it with
  a new key), delete `client.crt` in the VM collectors' `tls`
  directories and rerun the `deploy-instrumentations:*` jobs.
- **Gateway, trusted path**: `collector-gateway/otel-gateway-collector.yaml`
  has a `headers_setter` extension that forwards the `tenant_id` a
  trusted platform collector sent as `X-Scope-OrgID` to Mimir/Loki/Tempo's
  exporters. Anything that doesn't set `tenant_id` falls back to
  `anonymous`.
- **Real rejection of non-onboarded tenants**: `headers_setter` alone
  doesn't validate `tenant_id`, and Mimir/Loki create a tenant
  implicitly on first write, so an instrumented-but-not-yet-onboarded
  system's telemetry would otherwise be silently accepted under the
  global default limits. `attributes/tag_tenant` +
  `filter/reject_unknown_tenants` (wired into all three client-facing
  pipelines) close this gap: anything whose `tenant_id` isn't
  `anonymous` or a real onboarded tenant is dropped. The allowlist is
  auto-generated by `scripts/provision.py`
  (`update_gateway_tenant_allowlist()`) and only rolled out via
  `tenants:rollout` (the gateway CR lives in
  `terraform/environments/tenants` specifically for this), not
  `deploy:observability-stack` - so a fresh platform deploy with no
  `tenants:rollout` run yet rejects **everyone**, this demo's own
  fixed-fleet baseline tenant (`4087-prod`) included. That's
  deliberate: instrumented-but-not-onboarded traffic should be dropped
  until onboarding is actually approved.
- **Client example**: the agent DaemonSet serves an entire node (every
  pod's host/kubelet metrics and logs, not one application), so it's
  tagged with the Cloud Container Plattform's `system_id`
  (`4087-prod`) rather than any one application's - see
  `instrumentation/platforms/4087-container-platform/config.yaml`. Tenant is
  `<system_id>-<env>`, not just `system_id` - a manifest can declare
  different budgets per environment, and a backend tenant can only
  carry one set of limits at a time.
- **Middleware/runtime tenants**: a dedicated resource that's
  exclusively and permanently provisioned per application - an
  application-server/language runtime, a database, a cache, or
  anything similar - never gets its own platform tenant, regardless of
  what kind of resource it is; its telemetry always reports under the
  application's own tenant instead, even if more than one application
  happens to use the same middleware/runtime/database *technology*
  (each app normally gets its own dedicated instance anyway, so
  there's nothing to actually share at the tenant level). This demo
  originally had three such tenants (`1295-prod` Tomcat, `3168-prod` a
  JVM runtime, `4139-prod` PostgreSQL) that got merged into their
  respective applications once checked - pure bookkeeping overhead
  with no real sharing behind them. Hard rule, not a case-by-case
  default: a genuinely shared, independently running service (one
  instance multiple apps actually talk to, not one provisioned fresh
  per application) would be real sharing worth a platform tenant -
  that's just not what any middleware/runtime/database in this demo
  is.
- **Tempo**: `multitenancy_enabled: true` in `helm/values/tempo-values.yaml`.
  Its metrics-generator automatically forwards the same tenant on its own
  `remote_write` to Mimir - no separate config needed. Verified
  directly: querying without `X-Scope-OrgID` returns `401`, with it
  `200`.
- **Grafana**: `helm/values/grafana-values.yaml` has exactly one static
  datasource, `Mimir-anonymous` (self-monitoring, genuinely
  tenant-agnostic). Every onboarded tenant's own triplet, 4087
  included, is a `datasources/<tenant_id>.yaml` ConfigMap
  instead, auto-generated and applied by `tenants:rollout` - see
  [Per-System Dashboards (Onboarding)](#b8-per-system-dashboards-onboarding)
  above. Offboarding doesn't delete that ConfigMap file - Grafana's
  file-based datasource provisioning only adds/updates, never deletes
  just because its source file disappears - so an offboarded tenant's
  file is rewritten to a permanent `deleteDatasources` tombstone
  instead (`_render_tombstone_configmap()` in `scripts/provision.py`),
  and `tenants:rollout` restarts the Grafana deployment every run so
  any pending tombstones actually take effect.
- **Budget enforcement**: the per-second rate limit and the daily
  budget are deliberately decoupled (`scripts/provision.py`'s
  `compute_overrides()`). Every tenant gets the same generic,
  size-independent rate/burst limit on every signal
  (`GENERIC_INGESTION_RATE_MB`/`GENERIC_INGESTION_BURST_MB`) - a pure
  platform-protection ceiling, unrelated to `size` - committed to
  `helm/values/{mimir,loki,tempo,pyroscope}-tenant-overrides.yaml` and
  applied by `tenants:rollout` (hot-reloaded, no pod restart; these are
  Mimir's own documented, standard mechanism for tenant-specific
  limits, not a workaround). The actual daily budget (still
  `size`-derived, `helm/values/ingestion-daily-budgets.yaml`) is
  tracked and enforced separately by the `ingestion-midnight-snapshot`
  CronJob (`terraform/environments/observability-stack/main.tf`,
  `scripts/ingestion-midnight-snapshot.py`), which runs every 2
  minutes. Each of the four signals (Mimir/Loki/Tempo/Pyroscope) has
  its own independent daily budget and is throttled independently -
  was one combined budget summed across all four signals until an
  NFR-05 pre-test audit found that blended together genuinely
  different bases (Loki/Tempo's real uncompressed bytes, Pyroscope's
  real but COMPRESSED bytes, Mimir's pure sample-count estimate, since
  it has no byte counter at all) as if they were one comparable unit,
  and meant a tenant heavy on one signal could throttle its other,
  unrelated signals too. Mimir's own budget stays in samples (its
  native unit) rather than a fabricated bytes value. A one-off
  `--reset-tenant` mode resets a single tenant immediately for demo
  pacing (see `demo:uc4-fix` in `.gitlab-ci.yml`) without waiting for a
  real rollover.

  Each tenant/signal's real usage since local midnight is computed
  fresh on every 2-minute run by querying Mimir directly with
  `sum by (tenant) (increase(<counter>{tenant=~".+"}[<seconds since
  midnight>s]))` - reset handling happens PER underlying series
  (instance/pod) before the outer sum, exactly matching how Prometheus
  itself requires counter resets to be handled (a plain "current minus
  the value snapshotted at day start" subtraction, this repo's earlier
  approach, cannot do this: it has no visibility into the individual
  samples in between, only two points). A second NFR-05 pre-test audit
  round found that earlier fix (a hand-rolled Python day-start-snapshot
  + incremental accumulator) still had three further confirmed bugs -
  all fixed by moving the whole computation server-side into Mimir
  instead: (1) a tenant already ingesting before this script's own
  first look at it (a late first daily run after a CronJob outage, or
  activity right at onboarding) had that usage silently excluded -
  `increase()` over the real wall-clock window since actual midnight
  has no such blind spot, since Mimir has always been storing the raw
  samples regardless of whether this script itself was watching yet;
  (2) a counter reset on ONE of several instances of the same signal
  was invisible whenever another instance was still growing at the
  same time, because the old approach summed every instance's raw
  counter together server-side BEFORE any reset-detection ever ran
  Python-side - `increase()` is applied per series (per instance)
  first, `sum by (tenant)` only wraps the already-compensated result
  afterward; (3) the dashboard/alert did their own separate "current
  minus a pushed day-start snapshot" subtraction, independently of (and
  able to silently disagree with) whatever this script itself was
  internally acting on - both now read one single, already-correct
  value this script pushes directly (`demo_ingestion_since_midnight`,
  paired with `demo_ingestion_daily_budget` on identical `{tenant,
  signal}` labels), no subtraction on their end at all. `--reset-tenant`
  keeps its demo-pacing behavior via a persisted per-tenant
  `reset_at` timestamp - that tenant's own since-midnight window then
  starts from its own reset time instead of real midnight, queried
  separately from every other tenant's shared window.

  Throttle/restore attempts are also now confirmed before this
  script's own state is updated - previously a tenant could be marked
  throttled/restored even when the underlying runtime-ConfigMap write
  never actually happened (e.g. the ConfigMap was briefly missing),
  permanently skipping any retry for the rest of the day. Every
  2-minute run now reconciles "what SHOULD be throttled right now"
  (computed fresh from the since-midnight values above) against "what
  is CONFIRMED throttled" in state, in both directions - a failed
  attempt, in either direction, simply stays unresolved and is retried
  automatically on the very next run, with no separate "restore
  everyone" step needed for a day rollover specifically. Throttled
  values themselves are derived from `THROTTLE_RATE_MB` (a near-zero
  rate) fed through the exact same per-field unit-conversion formulas
  the normal rate/burst uses, not a single raw constant substituted for
  every field regardless of its own unit - the latter used to be
  correct/negligible for Mimir's samples/sec and Tempo's bytes/sec
  fields but genuinely wrong for Loki's/Pyroscope's own `_mb` fields,
  where the old raw `1` meant a real, non-trivial 1 MB/s allowed rate
  rather than near-total blocking.

  Live cross-tenant consumption has its own dashboard, **Operator:
  Tenant Ingestion Budget** (`dashboards/shared/operator-tenant-
  budget.json`, no Mimir tenant federation involved - self-monitoring
  data lands under the `anonymous` tenant via `otel-gateway-
  collector.yaml`'s `prometheus/*-self` jobs): a daily budget-usage
  timeseries per tenant, four rate-vs-limit panels (one per signal),
  and three discard-rate panels (Pyroscope has no discard counter of
  its own, only client-side HTTP 429s). 4087's own dashboard carries a
  companion bar-gauge of the same budget-usage view, since 4087's owner
  is effectively the platform operator; every other tenant's own
  dashboard carries just its own "Ingestion Budget Usage" panel, same
  formula, filtered to itself.

#### B10. Telemetry Schema

Full field reference: [`instrumentation/schema/core.yaml`](../instrumentation/schema/core.yaml) - a
layered resource-attribute schema (Core → Platform Extension →
Application Extension), adopted from an external design doc and
adapted to this demo's actual fleet. Separate from and complementary
to Multi-Tenancy above: `tenant_id`/`X-Scope-OrgID`
([B9](#b9-multi-tenancy-onboarding)) controls which backend tenant a
signal lands in; this schema controls the shape of the resource
attributes attached to the signal itself, regardless of which tenant
it lands in.

This maps onto a 3-layer directory model, indexed at
[`instrumentation/README.md`](../instrumentation/README.md): **1. schema**
(`instrumentation/schema/core.yaml`, one place, applies everywhere) → **2.
platform/runtime templates** (`instrumentation/platforms/*/`,
`instrumentation/middleware/*/` - one folder per platform type/technology,
each with its own guide) → **3. application templates**
(`instrumentation/applications/*/` - one folder per app, extending its own
platform/runtime template).

- **Core Schema**: every system's telemetry carries `service.name`/
  `service.namespace` (already this repo's convention everywhere),
  plus `deployment.environment`, `platform.type`, `platform.vendor`,
  `app.owner`, `app.cost_center`, `app.size_class` - the last four are
  new. `platform.type`/`platform.vendor` are static per platform
  template (`instrumentation/platforms/*/config.yaml`, the agent DaemonSet);
  the rest is per-tenant, sourced from `manifests/schema.json`
  (`owner.team`, `cost_center`, `environments[].env`/`size` -
  `cost_center` is a new manifest field, added alongside this schema)
  and filled in via the same manual-placeholder pattern `<TENANT_ID>`
  already used at onboarding time (`instrumentation/middleware/*`,
  `instrumentation/platforms/*/config.yaml`).
- **Platform Extensions**: one guide + template per this demo's 5 real
  platform types (Linux, Windows, Kubernetes, network device, object
  storage) - plus two reference-only guides (NetApp, Mainframe z/OS)
  demonstrating the model's extensibility beyond this fixed fleet,
  clearly marked as not deployed here (`instrumentation/schema/core.yaml`'s
  `platform_extensions.not_present`).
- **Application Extensions**: `app.<service.name>.*` namespacing, one
  guide per this demo's actual apps (Java/Tomcat 4711, .NET 4722,
  Kundenverwaltung 4721, the polyglot Astronomy Shop 4720) under
  `instrumentation/applications/`, plus a blank `_template/` for onboarding a
  new one.
- **Cardinality Rule**: which attribute tier is safe as a metric
  label, which never is - enforced at the gateway
  (`transform/strip_high_cardinality_metrics` in
  `collector-gateway/otel-gateway-collector.yaml`, metrics
  pipeline only, since `prometheusremotewrite`'s
  `resource_to_telemetry_conversion` would otherwise promote every
  resource attribute to a Mimir label) rather than relying on every
  client getting it right - generalizes the same protective principle
  behind the `processes` scraper removal (see [Known
  Pitfalls](known-pitfalls.md#known-pitfalls)) into an explicit, reusable rule.
- **Baggage**: scoped implementation - `correlation.request_id`
  (any single HTTP service) is live in Kundenverwaltung/
  Spesenabrechnung, the only two apps in this fleet with source code
  this repo owns, verified live via a real request on both;
  `correlation.transaction_id` (crosses multiple services) only
  applies to UC3/Astronomy Shop, the only real multi-hop application
  call chain in this fleet, via a demo-trigger script rather than app
  code this repo doesn't own - verified live that it does **not**
  surface as a span attribute there, a confirmed upstream gap
  (`open-telemetry/opentelemetry-demo#1572`), not something this repo
  can fix without that chart's own source - see
  `instrumentation/schema/core.yaml`'s Baggage Schema section for the
  full reasoning and [Known Pitfalls](known-pitfalls.md#known-pitfalls) for how this
  was verified.
- **Versioning/governance**: Git/PR review only - no OTel
  `schema_url`/`schemaprocessor` runtime enforcement (considered, not
  adopted: real operational complexity with no clear payoff at this
  repo's single-schema, single-repo scale).

#### B11. Alerting

Runs automatically as part of the `tenants:rollout` job (moved from
`deploy:observability-stack` after a live bug - see
[`alerting/README.md`](../alerting/README.md)'s own top section): Grafana
Unified Alerting rules plus two contact points in
[`alerting/shared/openclaw-webhook.yaml`](../alerting/shared/openclaw-webhook.yaml):
`openclaw` (webhook) and `no-delivery` (the root receiver).
The notification policy routes three alerts there - UC1 (`1286 Linux
Basis - host CPU > 80%`), UC2 (`1229 Windows Server Basis - Print
Spooler service crashed`) and `Ingestion budget not enforced for a
tenant`. Everything else ends at the `no-delivery` receiver
(e-mail, no SMTP configured on purpose - demo): those alerts are only visible as Firing/Pending/Normal
on Grafana's Alerting page, and Grafana logs a harmless "SMTP not
configured" error per notification. Same
ConfigMap+sidecar auto-discovery mechanism as
[B6](#b6-per-tenant-datasourcesdashboards)/[B7](#b7-dashboards)
(`sidecar.alerts`, label `grafana_alert: "1"` - see
[`helm/values/grafana-values.yaml`](../helm/values/grafana-values.yaml)),
applied via `terraform/environments/tenants/main.tf`'s
`kubernetes_config_map.alert_rules` (`for_each` over `alerting/
{platforms,applications}/*/alert-rules.yaml` + `alerting/shared/*.yaml`
- see [`alerting/README.md`](../alerting/README.md)) - 4 fixed,
hand-authored files, not manifest-generated like the rest of that
Terraform state, but deployed alongside it since each rule is pinned to
one of these same onboarded systems.

Exactly one rule per Demo Use Case (four files, four rules), each in
its own Grafana folder named after its system's `system_id` (e.g.
`1286`) - the same single-level folder its own dashboard lives in, not
grouped by Use Case (see [`alerting/README.md`](../alerting/README.md)'s
own table for the current file-to-folder mapping). Every rule's query
stage references a real Mimir or Loki `datasourceUid` (depending on
the signal that Use Case's alert watches) - explicit and deterministic
(`mimir-<tenant_id>`/`loki-<tenant_id>`), added to both
`helm/values/grafana-values.yaml`'s static `Mimir-anonymous` and every
per-tenant datasource `scripts/provision.py` generates (see that
script's `_render_datasource_configmap()`) - Grafana's file
provisioning otherwise auto-generates a uid non-deterministically,
which this independently-authored YAML couldn't reference.

Same "not live until onboarded" caveat as every other per-tenant
artifact in this repo (datasources/dashboards/instrumentation) - a
rule's datasource only resolves once the corresponding system is
actually onboarded.

#### B12. Continuous Profiling (Pyroscope)

Runs as part of the `deploy:observability-stack` job: a `pyroscope`
`helm_release` (microservices/distributed mode, matching Loki/Tempo/
Mimir - see [`helm/values/pyroscope-values.yaml`](../helm/values/pyroscope-values.yaml)),
Azure Blob backend (container `pyroscope-data`), multi-tenant via the same
`X-Scope-OrgID` convention as every other signal - `multitenancy_enabled: true`
set explicitly in `pyroscope-values.yaml`, since (unlike Mimir, which
defaults to multi-tenant on) Pyroscope defaults this to `false` the
same way Loki (`auth_enabled`) and Tempo (`multitenancy_enabled`) do.
One replica per component (9 components in this chart's v2
microservices architecture) rather than the chart's own production-
scale defaults (2-3 each, 15+ pods) - this repo's cluster has already
hit a real capacity limit once before with a smaller telemetry
footprint than that (see Known Pitfalls).

**Found live on the first real `deploy:observability-stack` run**,
not caught by any offline validation: two of `pyroscope-values.yaml`'s
top-level keys were wrong (a plausible-looking `pyroscopeConfig:`
wrapper instead of `pyroscope.structuredConfig`, and a bare
`microservices:` instead of `architecture.microservices`) - Helm
accepts unknown top-level keys instead of rejecting them, so the
`helm_release` apply reported success while actually running single-
binary mode with no S3 storage configured at all, and the
`pyroscope-internal` Service's selector (which assumed microservices
mode) matched zero pods. Fixed by verifying every key directly against
the chart (`helm show values grafana/pyroscope` + `helm template`,
chart 2.2.1) rather than by pattern-matching against Mimir/Tempo's
differently-shaped values files - **confirmed on the next real
redeploy**: all 9 microservices pods `Running`/`Ready`, real objects
landing in the `pyroscope-data` container
(`adaptive_placement/placement_rules.binpb` and
`placement_stats.binpb`, written by the metastore) - at the time in
MinIO, since replaced by Azure Blob Storage.

**Found live during the post-e2e instrumentation/backend-acceptance
check**: `multitenancy_enabled` had been left unset, and Pyroscope
defaults it to `false` - so every client's `X-Scope-OrgID` header
(set via `PYROSCOPE_TENANT_ID`) was silently ignored and all profile
data landed under the single tenant `anonymous`, confirmed via the
distributor's own `pyroscope_distributor_push_batch_series_sum{tenant=...}`
metric (413 real pushes, all tagged `anonymous`, before the fix).
Fixed by setting `pyroscope.structuredConfig.multitenancy_enabled: true`
- confirmed on the next `helm upgrade` that real app traffic
(4711/4721/4722) now lands under its correct tenant ID.

Unlike traces/metrics/logs, profile data does **not** flow through
[`collector-gateway/otel-gateway-collector.yaml`](../collector-gateway/README.md) -
OTLP profiles is still an experimental, actively-changing part of the
OTel spec as of the collector version pinned there, so app-side
Pyroscope client agents push to a small nginx **Pyroscope ingest proxy**
instead (internal LoadBalancer `pyroscope-internal` for the VMs, Service
`pyroscope-ingest` in the cluster). Pyroscope OSS has no authentication,
so the proxy does it (F03): Basic Auth with user = tenant_id and a
per-tenant password (`terraform/environments/tenants`, Secret
`pyroscope-ingest-<tenant_id>`), then sets `X-Scope-OrgID` from the
authenticated user, overwriting anything the client sent. Only the push
endpoints (`/ingest`, `/push.v1.PusherService/Push`) are forwarded;
query APIs aren't reachable through it. Password rotation:
`terraform apply -replace='random_password.pyroscope_ingest["<tenant_id>"]'`
in `terraform/environments/tenants`, then rerun that tenant's
instrumentation job (4721: `deploy-instrumentations:4721-kundenverwaltung`).

No static `Pyroscope-anonymous` datasource, unlike `Mimir-anonymous` -
nothing in this repo ever profiles under the "anonymous" tenant (every
app agent tags with its own tenant), so there'd be nothing for it to
show; every onboarded tenant still gets its own `Pyroscope-<tenant_id>`
datasource via `scripts/provision.py`'s `_render_datasource_configmap()`,
same as Mimir/Loki/Tempo. No dedicated dashboard - flame graphs are
viewed via Grafana Explore, same treatment this repo already gives Tempo's
service graph (see [B7](#b7-dashboards)).

**Instrumented in this fleet**, all three via a downloaded agent/
profiler binary plus environment variables - zero application
source-code changes: 4711 Mitarbeiterverzeichnis (Pyroscope Java agent
alongside the OTel javaagent, `instrumentation/middleware/tomcat/tomcat.service.j2`),
4721 Kundenverwaltung (same Java-agent pattern, `terraform/environments/
fleet-4139-postgresql/main.tf`'s init-container download + conditional
`-javaagent:`), 4722 Spesenabrechnung (Pyroscope's .NET profiler - a
native CLR-profiler attach via a downloaded DLL and
`CORECLR_*`/`PYROSCOPE_*` environment variables, not a NuGet package or
`Program.cs` change - see `ansible/roles/middleware-dotnet/tasks/instrument.yml`).
4720 Astronomy Shop is explicitly out of scope (upstream-owned chart,
no source access - same precedent as Baggage's `transaction_id`
scoping above).

No per-tenant profiling budget/retention override exists - same "no
override file" precedent as Tempo, deliberately not Mimir/Loki's
pattern.

#### B13. OpenClaw AIOps Remediation (ai-ops-azure integration)

Runs via its own `deploy-aiops:aiops`/`destroy:aiops` jobs, a separate
Terraform state (`terraform/environments/aiops`) from
`observability-stack` - so the AI/OpenClaw component of the demo can be
deployed/destroyed independently of the rest of the platform: OpenClaw
(an LLM-based SRE agent, `ghcr.io/openclaw/openclaw`, running on Claude
via the subscription setup-token from [A7](#a7-claude-subscription-setup-token--openclaw-gateway-token)) as a `kubernetes_deployment_v1` in its own
`openclaw` namespace (not `observability-stack`'s `observability`
namespace) - no Helm chart exists for OpenClaw anywhere upstream
(checked the whole `openclaw` GitHub org), so it's plain `kubernetes_*`
resources, same idiom as `observability-stack`'s other small in-cluster
services (e.g. the `ingestion-midnight-snapshot` CronJob). Migrated from
the separate `ai-ops-azure` repo/VMs (see Open Points) - its dedicated
"monitoring" (Prometheus/Alertmanager) and "target" VMs are retired,
replaced by this platform's own Mimir/Grafana and the existing
`vm-rocky-demo`.

- **Workspace** (`openclaw/workspace-templates/` - structure and
  filenames adopted from a separate reference project, `openclaw-app`,
  content adapted for this repo's actual SSH-based/Grafana+Mimir
  environment rather than copied verbatim, since the original files
  assume a different setup - Kubernetes/OpenShift tooling access and a
  Prometheus/Alertmanager stack neither of which exist here):
  `AGENTS.md`/`IDENTITY.md`/`SOUL.md`/`USER.md` plus `openclaw.json`,
  mounted into the Pod via `kubernetes_config_map.openclaw_config` -
  all except `SOUL.md` are rendered with `templatefile()` (VM private
  IP, model, and the cosmetic agent/
  organisation/operator identity strings from [A7](#a7-claude-subscription-setup-token--openclaw-gateway-token),
  all overridable via CI/CD variables, all with a working default).
  `TOOLS.md` used to be a separate file here too, matching
  `openclaw-app`'s own reference structure - confirmed against
  OpenClaw's current docs and its own `doctor` command that this is
  outdated: the current convention folds tool/environment notes into a
  `## Tools` section inside `AGENTS.md` itself, not a standalone file
  (`doctor` explicitly flags a standalone `TOOLS.md` for archival/merge).
  Consolidated accordingly.
  A PVC (`openclaw-home`) persists OpenClaw's own generated
  runtime state (session history) across pod restarts - `strategy:
  Recreate` on the Deployment - an RWO PVC can't be mounted by the old
  and the new pod at the same time, so a rolling update deadlocks.
- **Runbooks** (`/sre/runbooks/*.md`, repo-level, not nested under
  `openclaw/` - the same top-level convention `ai-ops-azure` already
  used): deliberately extensible - `kubernetes_config_map.
  openclaw_runbooks` discovers every `*.md` file here via `fileset()`,
  so adding a new runbook is just adding one file and committing it,
  picked up automatically the next time this Terraform state is
  applied, no code change needed.
- **Remediation credentials**: a dedicated SSH keypair
  (`tls_private_key.openclaw_ssh`), deliberately *not* the same key
  `fleet-1286-linux-basis`'s own Terraform state generates for
  Ansible - reading that one here would need a live cross-state
  Terraform read, coupling two otherwise-independent CI jobs for no
  reason. Its public half is installed onto `vm-rocky-demo` via
  `azurerm_virtual_machine_run_command` - a native `azurerm`-provider
  resource, not a `local-exec`/`az`-CLI workaround (this job's own
  container image has no `az` CLI installed).
- **Least privilege on the VM (F07)**: OpenClaw logs in as its own
  user `openclaw`, not as the admin `rocky` (unrestricted sudo). Its
  only root privilege is `sudo /usr/local/sbin/demo-uc1-stop` without
  arguments: the wrapper kills only PIDs from the root-owned
  `/tmp/demo-uc1-cpu.pids` whose process is still a root-owned
  `while :; do :; done` loop. That the agent can only do what the
  runbooks need is enforced by the VM, not just by its prompt; a
  runbook that needs another privileged command needs its own wrapper
  plus sudoers entry in the same run command. The `authorized_keys` entry
  carries `restrict` (no forwarding, no PTY).
- **Host key pinning (F08)**: the same run command prints the VM's SSH
  host key; it becomes `/home/node/.ssh/known_hosts` in the pod and
  OpenClaw connects with `StrictHostKeyChecking=yes`.
- **Network policy** (enforced by Calico, `network_policy = "calico"` in
  `terraform/modules/aks-cluster` - found live that the cluster ran
  without any policy engine at first, so these policies existed but
  were not enforced): egress restricted to DNS, HTTPS (Anthropic API),
  and SSH to `vm-rocky-demo`'s private IP specifically - not scoped to
  `api.anthropic.com`'s exact IPs, since this cluster's CNI (Azure
  CNI) can only match NetworkPolicy on IP/CIDR, never hostname; still
  meaningfully tighter than `ai-ops-azure`'s own unrestricted egress.
  Ingress restricted to Grafana's own pods (webhook calls) and
  Traefik's own pods (public HTTPS access, see below) only - both run
  in different namespaces from OpenClaw's own `openclaw`, so each gets
  its own `from` entry combining a `namespace_selector` (matching
  Kubernetes' own auto-applied `kubernetes.io/metadata.name` label)
  with a `pod_selector` where one's needed (Traefik's own namespace is
  dedicated solely to it, so a namespace-level allow is sufficient
  there). Plus each node IP as a `/32` `ip_block`: Traefik runs with
  `hostNetwork: true`, so its requests arrive from a node IP, which no
  namespace selector matches - without these, an enforcing policy engine
  only lets Traefik through when it runs on OpenClaw's own node.
- **`gateway.trustedProxies` vs. Azure CNI's flat address space**:
  OpenClaw only trusts forwarded-client-IP headers (`X-Forwarded-*`)
  from source IPs listed in `trustedProxies`, and rejects (403
  `proxy_attribution_required`) any request whose peer IP - or the
  client IP those headers attribute - itself falls inside that same
  list, treating it as unverifiable proxy-shaped traffic. Found live:
  with Azure CNI, nodes and pods share one flat VNet subnet, so there
  is no CIDR that contains Traefik (needed, for the browser login path)
  without also containing ordinary pods like Grafana (calling
  OpenClaw's webhook directly, with no forwarded headers of its own -
  correctly rejected once its own pod IP was inside `trustedProxies`
  too). The fix is at the network layer, not a config compromise:
  Traefik runs with `hostNetwork: true` (`helm/values/traefik-values.yaml`),
  so its effective source IP becomes the AKS node's own IP - the one
  identity in this cluster genuinely disjoint from every regular pod's
  IP. `trustedProxies` is then scoped to just the current node IPs,
  computed at every `deploy-aiops:aiops` apply via
  `data.kubernetes_nodes.all` (`terraform/environments/aiops/main.tf`)
  rather than hardcoded, so it self-corrects if the node pool is ever
  resized or a node replaced (the only residual gap is a node change
  happening between two applies of this state - not something this
  demo's fixed-size, non-autoscaling node pool does on its own). This
  keeps both paths working simultaneously: the browser login through
  Traefik, and Grafana's direct webhook call, which no longer needs
  `trustedProxies` to recognize it at all.
- **Public HTTPS access + login**: `openclaw.sre.example.com`, same
  Traefik `IngressRoute` + cert-manager `Certificate` pattern as
  Grafana's (`k8s/ingress/openclaw-{cert,ingressroute}.yaml`) - skipped
  entirely when cert-manager isn't configured yet ([A6](#a6-create-the-cert-manager-service-principal)),
  same guard `observability-stack-crs` already uses for Grafana's pair.
  Both manifests live directly in this state (not a separate `-crs`
  one like Grafana's) since the ClusterIssuer/CRDs they depend on are
  already guaranteed to exist by the time `deploy-aiops:aiops` runs (its
  own stage comes after `deploy:observability-stack`, not alongside its
  first-ever install). Login is two gates:
  1. **Gateway token** - `openclaw.json` sets `gateway.auth.mode:
     "token"`, so the browser prompts for a token, checked against the
     same `OPENCLAW_GATEWAY_TOKEN` already injected into the Pod's
     environment (no separate credential to manage).
  2. **One-time device pairing** - after a successful token login, a
     browser the gateway doesn't know yet shows "Approve this browser"
     with a request ID. Approve it once on the gateway host:

     ```bash
     kubectl exec -n openclaw deploy/openclaw -c openclaw -- \
       node /app/dist/index.js devices approve <requestId>
     ```

     The pairing is stored on the `openclaw-home` PVC, so it survives
     Pod restarts and redeploys; only a new browser/profile (or a
     `destroy:aiops`, which deletes the PVC) needs it again. Found
     live: `controlUi.dangerouslyDisableDeviceAuth` no longer skips
     this - OpenClaw has retired the key and ignores it (removed from
     `openclaw.json`). Full automation would need
     `gateway.auth.mode: "trusted-proxy"` with
     `trustedProxy.deviceAutoApprove` behind an SSO proxy - deliberately
     not done, the pairing is a cheap second gate on top of the token.

  `ai-ops-azure`'s own OpenClaw dashboard had **no** auth at all
  (confirmed live: its README lists dashboard credentials as "None",
  world-reachable on plain HTTP) - deliberately not repeated here.
- **Trigger**: UC1's existing alert (`1286 Linux Basis - host CPU >
  80%`) - no new alert was built for this. A Grafana webhook contact
  point (`alerting/shared/openclaw-webhook.yaml`, Grafana's own
  `apiVersion: 1` provisioning format, applied the same
  ConfigMap+sidecar way as every alert rule) calls OpenClaw's own
  `gateway.hooks.*` endpoint (`/hooks/agent`) directly, over the
  in-cluster ClusterIP Service - **no separate bridge/relay service**
  (unlike `ai-ops-azure`'s own Python `alertmanager-bridge.py`):
  confirmed against Grafana's own webhook-notifier source that
  `authorization_scheme`/`authorization_credentials` cover the
  required Bearer auth (`OPENCLAW_HOOKS_TOKEN`, a separate secret from
  `OPENCLAW_GATEWAY_TOKEN` used by browser login), and a Custom Payload
  template (built with Grafana's `coll.Dict`/`data.ToJSON` template
  functions, not hand-assembled JSON text, so label values are always
  correctly escaped) produces the exact `{agentId, message}` body the
  endpoint expects from the alert's own labels. `/hooks/agent` was
  chosen over the more obvious `/v1/chat/completions` specifically
  because it responds asynchronously (HTTP 200 on admission) - found
  live: `/v1/chat/completions` is synchronous, and once the agent
  actually started reading a runbook and executing SSH commands (real
  work takes noticeably longer than a quick reply), it regularly
  exceeded Grafana's own webhook client timeout, which logged the
  notification as failed even though OpenClaw had already received it
  and was processing it correctly.
- **Runbook matching**: entirely OpenClaw's own agent logic
  (`AGENTS.md`'s "## Tools" section, "Search Order for Incoming
  Alerts"), not anything this
  repo's own code decides - the alert rule sets an explicit
  `runbook_key` label (not derived from its own human-readable title),
  which the webhook template passes through as `Runbook-Key` in the
  forwarded message; OpenClaw looks up `workspace/runbooks/
  <Runbook-Key>.md` and either follows it automatically or falls back
  to proposing options and waiting for a human. UC1's `runbook_key`
  (`1286-linux-basis-hostcpuhigh`, naming convention:
  `<system_id>-<system-slug>-<condition>`) matches `/sre/runbooks/
  1286-linux-basis-hostcpuhigh.md` (mirrors `demo:uc1-fix`'s own
  remediation commands exactly) - this alert demonstrates the
  autoremediation path; a `runbook_key` with no
  matching file falls back to human-in-the-loop automatically, no
  separate code path needed for that case - demonstrated for real by
  UC2's own alert (`1229 Windows Server Basis - Print Spooler service
  crashed`), routed to the same `openclaw` contact point with its own
  `runbook_key` (`1229-windows-server-basis-spoolercrash`) that has
  **no** matching file under `/sre/runbooks/` on purpose: OpenClaw
  analyzes the alert independently and proposes remediation options in
  chat instead of executing anything, since there's nothing here it's
  pre-authorized to run.
- **What's deliberately not adopted from `openclaw-app`**: only its
  workspace-template *structure/filenames* were reused (see above) -
  not its full MITM egress-proxy sidecar with credential-injecting
  domain allowlisting, driven by an "OpenClaw Operator" CR. That's an
  optional hardening layer, not a requirement for the model provider
  itself (the subscription setup-token is passed directly as an env
  var, no proxy-injected credential). Its remediation model is also
  Kubernetes-native (`kubectl`/`oc` against the cluster itself), which
  doesn't apply here - this integration's remediation target is an
  external Azure VM, not a Kubernetes workload.

### C. Fleets (Pipeline)

Provisioning for the demo fleet's VMs and Kubernetes apps
(`deploy-fleets:*`, eight CI jobs, ID-prefixed and staged in dependency
tiers): **platform-basis** (1229 Windows Server Basis, 1286 Linux
Basis, 1294 Netzwerk Basis, 4015 Filestorage - each only needs
`deploy:observability-stack`) runs first, then **applications** (4711
Mitarbeiterverzeichnis, running on Apache Tomcat - Tomcat's own
JVM/app-server telemetry reports under this same tenant, not a
separate middleware one, since it's only ever used by this one app;
4720 OTel Astronomy Shop Demo; 4721 Kundenverwaltung, whose own job
also provisions its dedicated PostgreSQL database - same "exclusively
used by one app" reasoning as Tomcat above, see Multi-Tenancy's
"Middleware/runtime tenants" note; 4722 Spesenabrechnung, needs 1229).
Every system comes up with **no telemetry reaching this platform
yet** - deliberately, see each script's own comment for how (inert
OTLP endpoint, `INSTRUMENT` toggle, bare collector config, or simply
not installing the collector at all yet, depending on the system).

1286-linux-basis/1229-windows-basis are provisioned via Terraform
(`deploy-fleets:1286-linux-basis`/`deploy-fleets:1229-windows-basis`,
each its own state, both a call to the reusable
[`terraform/modules/client-vm`](../terraform/README.md) module), which
creates the VM plus its NIC/Public IP/NSG explicitly, using the same
naming `az vm create` used to generate automatically. The SSH
key/admin password Terraform generates for each are read by the
Ansible jobs via `terraform output`. `destroy:1286-linux-basis`/
`destroy:1229-windows-basis` tear both down the same way.

**Management access (F08/F10)**:

| Port | Allowed from | Server identity checked by |
|---|---|---|
| SSH 22 (vm-rocky-demo) | GitLab runner public IP (`mgmt-gitlab-runner-pip`, looked up by name) + `VirtualNetwork` (OpenClaw via peering) | host key read over the Azure control plane (`terraform output ssh_host_public_key`), `StrictHostKeyChecking=yes` |
| WinRM 5986 (vm-windows-demo) | same | self-signed listener certificate with the public IP as SAN, created on the VM by run command `pin-winrm-cert`; pinned via `ansible_winrm_ca_trust_path` (`terraform output winrm_server_cert_pem`) |
| RDP 3389 (vm-windows-demo) | any | - |

**Accepted exception**: RDP stays open to any source - interactive
presenter access from changing networks, login only with the random
20-character admin password. Deliberate demo trade-off (user decision),
not suitable for production; there it would be Azure Bastion or a
source restriction. SSH from your own machine: go through the runner, or
use `az vm run-command`.

Each job is independently (re)runnable via `needs: optional: true`.

The four applications each get public web access as part of their own
`deploy-fleets:*` job (provisioning-scoped, not telemetry-scoped) - the
two in-cluster apps via a Traefik IngressRoute + cert-manager
Certificate + DNS record (same pattern Grafana uses), the two VM apps
via an NSG rule opening port 8080 (plus, for the Windows VM, a matching
Windows Firewall rule - NSGs and the guest OS's own firewall are
independent). All survive a full destroy + rebuild automatically, same
as everything else in `deploy-fleets:*` - see [Runbook](demo.md#runbook) for
the resulting URLs.

### D. Instrumentations (Pipeline)

Adds the OTel collector/agent/SDK config that actually sends telemetry
to this platform (`deploy-instrumentations:*`, eight CI jobs, mirrored
1:1 to the `deploy-fleets:*` jobs above, same tier order and
dependency staging). In reality this step happens in each platform/
application's own repo, run by the team that owns it - it only lives
here because this demo's "applications" don't have separate repos of
their own. Each job is independently (re)runnable via `needs: optional:
true`, same as its `deploy-fleets:*` counterpart.
