# OTel Demo Environment on AKS

[![CI](https://github.com/benschwarz1982/o11y-otel-lgtmp/actions/workflows/ci.yml/badge.svg)](https://github.com/benschwarz1982/o11y-otel-lgtmp/actions/workflows/ci.yml)
[![Terraform](https://img.shields.io/badge/Terraform-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-EE0000?logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)](https://helm.sh/)
[![Azure](https://img.shields.io/badge/Azure-0078D4?logo=microsoftazure&logoColor=white)](https://azure.microsoft.com/)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-000000?logo=opentelemetry&logoColor=white)](https://opentelemetry.io/)
[![Grafana](https://img.shields.io/badge/Grafana-F46800?logo=grafana&logoColor=white)](https://grafana.com/)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-000000?logo=data:image/svg%2Bxml;base64,PHN2ZyB2aWV3Qm94PSIwIDAgMTIwIDEyMCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8ZGVmcz4KICAgIDxsaW5lYXJHcmFkaWVudCBpZD0ibG9ic3Rlci1ncmFkaWVudCIgeDE9IjAlIiB5MT0iMCUiIHgyPSIxMDAlIiB5Mj0iMTAwJSI+CiAgICAgIDxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiNmZjRkNGQiLz4KICAgICAgPHN0b3Agb2Zmc2V0PSIxMDAlIiBzdG9wLWNvbG9yPSIjOTkxYjFiIi8+CiAgICA8L2xpbmVhckdyYWRpZW50PgogIDwvZGVmcz4KICA8IS0tIEJvZHkgLS0+CiAgPHBhdGggZD0iTTYwIDEwIEMzMCAxMCAxNSAzNSAxNSA1NSBDMTUgNzUgMzAgOTUgNDUgMTAwIEw0NSAxMTAgTDU1IDExMCBMNTUgMTAwIEM1NSAxMDAgNjAgMTAyIDY1IDEwMCBMNjUgMTEwIEw3NSAxMTAgTDc1IDEwMCBDOTAgOTUgMTA1IDc1IDEwNSA1NSBDMTA1IDM1IDkwIDEwIDYwIDEwWiIgZmlsbD0idXJsKCNsb2JzdGVyLWdyYWRpZW50KSIvPgogIDwhLS0gTGVmdCBDbGF3IC0tPgogIDxwYXRoIGQ9Ik0yMCA0NSBDNSA0MCAwIDUwIDUgNjAgQzEwIDcwIDIwIDY1IDI1IDU1IEMyOCA0OCAyNSA0NSAyMCA0NVoiIGZpbGw9InVybCgjbG9ic3Rlci1ncmFkaWVudCkiLz4KICA8IS0tIFJpZ2h0IENsYXcgLS0+CiAgPHBhdGggZD0iTTEwMCA0NSBDMTE1IDQwIDEyMCA1MCAxMTUgNjAgQzExMCA3MCAxMDAgNjUgOTUgNTUgQzkyIDQ4IDk1IDQ1IDEwMCA0NVoiIGZpbGw9InVybCgjbG9ic3Rlci1ncmFkaWVudCkiLz4KICA8IS0tIEFudGVubmEgLS0+CiAgPHBhdGggZD0iTTQ1IDE1IFEzNSA1IDMwIDgiIHN0cm9rZT0iI2ZmNGQ0ZCIgc3Ryb2tlLXdpZHRoPSIzIiBzdHJva2UtbGluZWNhcD0icm91bmQiLz4KICA8cGF0aCBkPSJNNzUgMTUgUTg1IDUgOTAgOCIgc3Ryb2tlPSIjZmY0ZDRkIiBzdHJva2Utd2lkdGg9IjMiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPgogIDwhLS0gRXllcyAtLT4KICA8Y2lyY2xlIGN4PSI0NSIgY3k9IjM1IiByPSI2IiBmaWxsPSIjMDUwODEwIi8+CiAgPGNpcmNsZSBjeD0iNzUiIGN5PSIzNSIgcj0iNiIgZmlsbD0iIzA1MDgxMCIvPgogIDxjaXJjbGUgY3g9IjQ2IiBjeT0iMzQiIHI9IjIuNSIgZmlsbD0iIzAwZTVjYyIvPgogIDxjaXJjbGUgY3g9Ijc2IiBjeT0iMzQiIHI9IjIuNSIgZmlsbD0iIzAwZTVjYyIvPgo8L3N2Zz4K)](https://openclaw.ai/)

Demo observability platform based on OpenTelemetry (metrics, logs, traces,
profiles) with the Grafana LGTM+P stack (Loki, Tempo, Mimir, Grafana,
Pyroscope) in **distributed mode**, deployed on Azure Kubernetes Service
(AKS), plus an autonomous AIOps remediation agent (OpenClaw, running on
Claude via a Claude Pro/Max subscription) that reacts to Grafana alerts and remediates issues over SSH -
autonomously when a matching runbook exists, human-in-the-loop otherwise.
Public access via Traefik + cert-manager + Let's Encrypt (Azure DNS
DNS-01) on a dedicated subdomain.

Covered client types: Kubernetes, Linux, Windows, network devices, file storage.

**Scope**: this repo owns the platform - building AKS and the LGTM+P
stack on it, the OpenClaw AIOps remediation agent, and deploying every
platform/application (as Kubernetes workloads or on VMs) onto it - the
onboarding *process* itself (request schema, self-service form, manifest
validation, MR automation, per-tenant provisioning, all under
`manifests/`/`form/` and the `tenants` CI stage - see
[Processes](#processes)) - and its own SRE runbooks (`sre/runbooks/`,
consumed by OpenClaw, extensible without any code change).

## Table of Contents

- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [CI/CD: GitHub Actions and GitLab CI](#cicd-github-actions-and-gitlab-ci)
- [Deployment](#deployment)
- [Processes](#processes)
- [Scheduled Scans](#scheduled-scans)
- [Demo](#demo)
- [Destroy](#destroy)
- [Known Pitfalls](#known-pitfalls)

## Project Structure

```
.
├── .github/             # GitHub Actions workflows, issue form (docs/github-actions.md)
├── .gitlab-ci.yml       # GitLab CI pipeline (validate → deploy → tenants → destroy)
├── ci/                  # CI images + scripts shared by both pipelines
├── bootstrap/           # One-time Azure/runner setup for GitHub Actions
├── manifests/           # Onboarding request manifests
├── form/                # Onboarding form (GitHub/GitLab Pages)
├── scripts/             # Bootstrap/onboarding scripts
├── helm/values/         # LGTM+P Helm values
├── collector-gateway/   # Central OTel Collector gateway
├── k8s/ingress/         # cert-manager + Traefik resources
├── datasources/         # Per-tenant Grafana datasources
├── dashboards/          # Grafana dashboards (JSON)
├── alerting/            # Grafana Alerting rules + OpenClaw webhook
├── openclaw/            # OpenClaw workspace templates + model config
├── sre/runbooks/        # Remediation runbooks OpenClaw follows
├── instrumentation/     # OTel Collector configs
├── app/                 # Demo application source
├── terraform/           # IaC (AKS, network, DNS)
└── ansible/             # VM config management
```

## Prerequisites

- Azure CLI (`az`), logged in (`az login`) - typically via the Azure Cloud
  Shell, since `az`/`kubectl`/`helm`/`terraform` are pre-installed there
- An Azure Resource Group you're allowed to create resources in (usually
  pre-provisioned in sandbox/playground subscriptions - check with
  `az group list --output table`)
- Access to the DNS provider of your parent domain (e.g. Cloudflare for
  `fs167.ch`) to delegate NS records for the subdomain
- For local `terraform init`: GitHub Actions setup - access to the state
  storage account (see [docs/github-actions.md](docs/github-actions.md#local-terraform));
  GitLab setup - a GitLab Personal Access Token (scope `api`) for the
  GitLab-managed state backend

## CI/CD: GitHub Actions and GitLab CI

**GitHub Actions is the primary pipeline**: OIDC to Azure without stored
secrets, Terraform state in Azure Storage, SHA-pinned actions, attested
CI images, self-service via issue form and pull requests. Setup, workflow
overview and the mapping of every GitLab job to its workflow:
[docs/github-actions.md](docs/github-actions.md).

**GitLab CI is kept as a fully working alternative** (`.gitlab-ci.yml`,
`ci/gitlab/`), for running the project on GitLab instead. Both drive the
same Terraform code, Ansible roles and scripts; only the Terraform state
backend differs (GitLab: its HTTP state backend, wired in by
`ci/gitlab/http-backend-override.sh`). Use one platform per environment at
a time - see [Moving the Pipeline to GitLab](#moving-the-pipeline-to-gitlab).

The step-by-step sections below name the pipeline steps by their GitLab
job names (`deploy:infra`, `tenants:rollout`, ...); the
[mapping table](docs/github-actions.md#gitlab-job--github-workflow)
gives the GitHub workflow and scope for each.

### Moving the Pipeline to GitLab

1. Import or push the repository into a GitLab project. The
   `.gitlab-ci.yml` runs unchanged; the self-service form switches to
   GitLab mode automatically when served from GitLab Pages - set
   `GITLAB_REPO_URL` in `form/index.html` to the new project.
2. Register the self-hosted runner (below) and create the GitLab CI
   service principal and CI/CD variables (README
   [section A](#a-one-time-bootstrapping-manual), A3-A7).
3. Rebuild from zero (`deploy:infra` → ...). Terraform state does not
   move between the platforms: destroy the environment with the
   platform that built it first, or import the resources into the new
   state.

### Self-Hosted GitLab Runner

Every job runs with `tags: [otel-demo]` (set via a top-level `default:`
block in `.gitlab-ci.yml`), so all CI runs go to a dedicated
self-hosted runner (`vm-gitlab-runner`) instead of GitLab.com's shared
runners - added after repeatedly hitting the shared-runner CI/CD
minutes quota during heavy pipeline testing (this repo's
fleet/instrument jobs are long-running and network-heavy).

**GitLab-side steps (done once, in the GitLab web UI, not automatable from
here):**
1. This repo's **Settings → CI/CD → Runners → "New project runner"**:
   tag `otel-demo`, executor `docker`, no other options changed. Creating it
   returns a one-time `glrt-...` authentication token (GitLab.com disabled
   the older shared `--registration-token` flow by default, so this is the
   only way to register a new runner now).

**Azure-side steps (own `mgmt-vnet`/`10.2.0.0/16`, deliberately separate
from `aks-vnet`/`observability-clients-vnet` - this runner has nothing to
do with the demo's own AKS/VNet peering setup):**
```bash
az network vnet create -g rg-bensc-001 -n mgmt-vnet \
  --address-prefix 10.2.0.0/16 \
  --subnet-name mgmt-gitlab-runner-subnet --subnet-prefix 10.2.1.0/24 \
  --location switzerlandnorth
az network public-ip create -g rg-bensc-001 -n mgmt-gitlab-runner-pip --sku Standard
az network nsg create -g rg-bensc-001 -n mgmt-gitlab-runner-nsg
# Source IP(s) allowed to SSH in - not left open to 0.0.0.0/0 (a persistent
# VM host is a standing attack surface, unlike the shared runners' fully
# ephemeral containers, or the demo fleet's own short-lived VMs). Repeat
# this rule (next priority) for every additional IP that needs access -
# e.g. your own, if you'll SSH in directly later.
az network nsg rule create -g rg-bensc-001 --nsg-name mgmt-gitlab-runner-nsg \
  --name AllowSSHInbound --priority 100 --access Allow --direction Inbound \
  --source-address-prefixes <IP>/32 --destination-port-ranges 22 --protocol Tcp
az vm create -g rg-bensc-001 -n vm-gitlab-runner \
  --image Canonical:ubuntu-24_04-lts:server:latest --size Standard_B2s \
  --admin-username azureuser --ssh-key-values <path-to-pubkey> \
  --vnet-name mgmt-vnet --subnet mgmt-gitlab-runner-subnet \
  --public-ip-address mgmt-gitlab-runner-pip --nsg mgmt-gitlab-runner-nsg \
  --location switzerlandnorth
```

**On the VM itself, over SSH:**
```bash
# Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker azureuser

# gitlab-runner
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" \
  | sudo os=ubuntu dist=noble bash
sudo apt install gitlab-runner -y
sudo usermod -aG docker gitlab-runner

# Registration - the glrt-... token from GitLab step 1 above
sudo gitlab-runner register --non-interactive \
  --url "https://gitlab.com/" --token "<glrt-...>" \
  --executor "docker" --docker-image "ubuntu:24.04" \
  --description "vm-gitlab-runner" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock"
sudo gitlab-runner verify
sudo gitlab-runner status
```

Raise the runner's parallelism in `/etc/gitlab-runner/config.toml` -
`concurrent = 4` (global) and `request_concurrency = 4` (in the
`[[runners]]` block) - then `sudo gitlab-runner restart`. With the
default of 1 the independent fleet/destroy jobs run one after another.

The SSH keypair used to reach the VM isn't in this repo or on the VM's
creator's machine by default - it only exists wherever it was
generated/downloaded at setup time. Back it up somewhere durable if you'll
need direct SSH access later; losing it doesn't affect the runner itself
(it keeps running as a systemd service either way), only your ability to
manage the VM directly.

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
export RESOURCE_GROUP=rg-bensc-001   # from the `az group list` output above
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

These only last for the current shell session - re-export them if you
open a new terminal.

#### A2. Create DNS Zone + Cloudflare NS Delegation

The Azure DNS subdomain zone is deliberately **not** managed by Terraform
(it's only referenced via `data "azurerm_dns_zone"`, see
[`terraform/README.md`](terraform/README.md)) - this decouples its
lifecycle from the AKS cluster/VNet destroy cycle. Without this
decoupling, every `destroy:infra` + `deploy:infra` cycle would
recreate the zone (new name servers), requiring a fresh, slow NS
delegation at the main DNS provider every single time. Only needed on the
very first setup - the zone stays stable afterwards:

```bash
az network dns zone create -g $RESOURCE_GROUP -n sre.fs167.ch
az network dns zone show -g $RESOURCE_GROUP -n sre.fs167.ch --query nameServers -o tsv
```

At your main DNS provider (e.g. Cloudflare for `fs167.ch`), enter the four
returned name servers as NS records for the subdomain:

| Type | Host | Value |
|---|---|---|
| NS | `sre` | `<ns1-xx.azure-dns.com.>` |
| NS | `sre` | `<ns2-xx.azure-dns.net.>` |
| NS | `sre` | `<ns3-xx.azure-dns.org.>` |
| NS | `sre` | `<ns4-xx.azure-dns.info.>` |

Check the delegation (after ~1 minute, can take up to ~1h):

```bash
dig NS sre.fs167.ch +short
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
ZONE_ID=$(az network dns zone show -g $RESOURCE_GROUP -n sre.fs167.ch --query id -o tsv)

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
G12 - see [Secrets](#secrets-key-vault)). **Rotating
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
[`terraform/README.md`](terraform/README.md).

#### B2. LGTM+P Stack + OTel Collectors

Runs via the `deploy:observability-stack` job (stage `deploy` in
`.gitlab-ci.yml`, started manually): two sequential `terraform apply`s,
[`terraform/environments/observability-stack`](terraform/README.md)
(namespaces, storage account, Loki/Tempo/Mimir/Grafana/Pyroscope/OTel Operator
`helm_release`s, dashboard `kubernetes_config_map`s, collector RBAC) then
[`observability-stack-crs`](terraform/README.md) (cert-manager issuers
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
[`helm/values/grafana-values.yaml`](helm/values/grafana-values.yaml)),
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
Pitfalls](#known-pitfalls)).

Grafana is then directly and securely reachable at
`https://grafana.sre.fs167.ch`. By default the admin password is
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
[Processes](#processes)) - no manual click
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
| `shared/otel-collector-15983.json` | shared | [grafana.com #15983](https://grafana.com/grafana/dashboards/15983/), revision 30, vendored as-is | Mimir-anonymous (its `$datasource` variable is regex-restricted to this one - see [Known Pitfalls](#known-pitfalls)) | Collector self-monitoring: receiver/processor/exporter throughput, refused/failed items, process health |
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
> [Known Pitfalls](#known-pitfalls). Deploy `kube-state-metrics`
> separately if you need classic K8s dashboards anyway.

The Tempo service graph needs no dashboard - it works automatically via
Explore > Tempo > Service Graph, since `metricsGenerator` is active with
`service-graphs`/`span-metrics` (data lands in Mimir).

#### B8. Per-System Dashboards (Onboarding)

Every onboarded system gets its own dashboard, stamped from a template
picked via the manifest's **required** `dashboard_template` field (see
[the schema](manifests/schema.json)) - required, not defaulted or
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
Grafana's `traces` type - see [Known Pitfalls](#known-pitfalls).

```bash
python3 scripts/generate-system-dashboard.py \
  --manifest manifests/platforms/4087-cloud-container-plattform.yaml
```

Writes `dashboards/<system_id>-<slug-of-name>.json` - one file/folder
per system regardless of environment count. Applied by
`deploy:observability-stack` for `shared/` dashboards,
`tenants:rollout` for every tenant's own (4087 included). Wired into
onboarding: `tenants:apply` runs this on every manifest merge and
commits the result - see [Processes](#processes).

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
[`manifests/schema.json`](manifests/schema.json) for the manifest
schema (`type: platform` = fleet-wide view, `type: application` = a
single app, optionally referencing one or more platforms via
`platform_refs`) and [Processes](#processes) for the
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

Full field reference: [`instrumentation/schema/core.yaml`](instrumentation/schema/core.yaml) - a
layered resource-attribute schema (Core → Platform Extension →
Application Extension), adopted from an external design doc and
adapted to this demo's actual fleet. Separate from and complementary
to Multi-Tenancy above: `tenant_id`/`X-Scope-OrgID`
([B9](#b9-multi-tenancy-onboarding)) controls which backend tenant a
signal lands in; this schema controls the shape of the resource
attributes attached to the signal itself, regardless of which tenant
it lands in.

This maps onto a 3-layer directory model, indexed at
[`instrumentation/README.md`](instrumentation/README.md): **1. schema**
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
  Pitfalls](#known-pitfalls)) into an explicit, reusable rule.
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
  full reasoning and [Known Pitfalls](#known-pitfalls) for how this
  was verified.
- **Versioning/governance**: Git/PR review only - no OTel
  `schema_url`/`schemaprocessor` runtime enforcement (considered, not
  adopted: real operational complexity with no clear payoff at this
  repo's single-schema, single-repo scale).

#### B11. Alerting

Runs automatically as part of the `tenants:rollout` job (moved from
`deploy:observability-stack` after a live bug - see
[`alerting/README.md`](alerting/README.md)'s own top section): Grafana
Unified Alerting rules plus exactly one contact point,
`openclaw` (webhook, [`alerting/shared/openclaw-webhook.yaml`](alerting/shared/openclaw-webhook.yaml)).
The notification policy routes three alerts there - UC1 (`1286 Linux
Basis - host CPU > 80%`), UC2 (`1229 Windows Server Basis - Print
Spooler service crashed`) and `Ingestion budget not enforced for a
tenant`. Everything else ends at Grafana's built-in
`grafana-default-email` receiver, which has no SMTP configured on
purpose (demo): those alerts are only visible as Firing/Pending/Normal
on Grafana's Alerting page, and Grafana logs a harmless "SMTP not
configured" error per notification. Same
ConfigMap+sidecar auto-discovery mechanism as
[B6](#b6-per-tenant-datasourcesdashboards)/[B7](#b7-dashboards)
(`sidecar.alerts`, label `grafana_alert: "1"` - see
[`helm/values/grafana-values.yaml`](helm/values/grafana-values.yaml)),
applied via `terraform/environments/tenants/main.tf`'s
`kubernetes_config_map.alert_rules` (`for_each` over `alerting/
{platforms,applications}/*/alert-rules.yaml` + `alerting/shared/*.yaml`
- see [`alerting/README.md`](alerting/README.md)) - 4 fixed,
hand-authored files, not manifest-generated like the rest of that
Terraform state, but deployed alongside it since each rule is pinned to
one of these same onboarded systems.

Exactly one rule per Demo Use Case (four files, four rules), each in
its own Grafana folder named after its system's `system_id` (e.g.
`1286`) - the same single-level folder its own dashboard lives in, not
grouped by Use Case (see [`alerting/README.md`](alerting/README.md)'s
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
Mimir - see [`helm/values/pyroscope-values.yaml`](helm/values/pyroscope-values.yaml)),
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
[`collector-gateway/otel-gateway-collector.yaml`](collector-gateway/README.md) -
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
- **Public HTTPS access + login**: `openclaw.sre.fs167.ch`, same
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
[`terraform/modules/client-vm`](terraform/README.md) module), which
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
as everything else in `deploy-fleets:*` - see [Runbook](#runbook) for
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

## Processes

How systems get onboarded, updated, and offboarded on this platform -
self-service, without ever needing access to this repo.

Sizing drives both onboarding and update requests: environment
retention (Eng: 10 days, AT/Prod: 30 days) × size class (S: 1 GB/day,
M: 10 GB/day, L: 25 GB/day) gives each tenant's storage/daily-ingestion
budget. `scripts/provision.py`'s `compute_overrides()` applies this
automatically for every tenant on every manifest merge (see below,
[B9](#b9-multi-tenancy-onboarding)) - no by-hand step in the actual
flow. `python3 scripts/calculate-ingestion-budget.py --app <appname>
--env <eng|at|prod> --size <S|M|L>` predates the rate-limit/daily-budget
decoupling ([B9](#b9-multi-tenancy-onboarding)) and still derives its
printed rate-limit YAML from size the old way - only its storage-budget
math still matches `compute_overrides()`; not updated since it's no
longer on the real path.

Two ways to submit any request: the **self-service form**
([`form/index.html`](form/index.html), published via GitLab Pages -
the `pages` job in [`.gitlab-ci.yml`](.gitlab-ci.yml), runs on every
push to `main`; see Deploy > Pages in the project for the current URL
and access-control setting, defaults to project-members-only) or the
**create-pipeline API** with your own GitLab token. The form holds no
credentials: it validates the input and opens GitLab's own **Run
pipeline** page for `main` with the variables prefilled
(`/-/pipelines/new?ref=main&var[SYSTEM_ID]=...`); the requester checks
them and clicks **Run pipeline** as their own, signed-in GitLab user.
Requesters therefore need a GitLab account that may run pipelines on
`main` (protected branch: allowed to merge or push). Such a
self-service pipeline contains only `validate:yaml`,
`validate:manifests` and the matching `tenants:*-mr` job - every other
job starts its `rules:` with `.skip_self_service_requests`.

An earlier version embedded a **pipeline trigger token** in the page.
That was not the harmless "publishable key" it looked like: a trigger
token lets anyone set **any** pipeline variable, including ones the
jobs trust (`CI_API_V4_URL`, `CI_PROJECT_ID`, `PIP_INDEX_URL`, ...) -
enough to send `GITLAB_API_TOKEN` to a foreign host or run arbitrary
code in a job that holds it. The token is gone and the `trigger`
pipeline source is no longer accepted (`workflow:`); **revoke any
remaining trigger token** under Settings > CI/CD > Pipeline trigger
tokens - the old one is still in git history. **One-time setup**:
Settings > CI/CD > Variables > **"Minimum role to use pipeline
variables"** must allow the requesters' role (at least **Developer**),
or GitLab refuses the prefilled variables.

Each of the three `tenants:*-mr` jobs below calls back into this
project's own API (branch, commit, MR) using a `GITLAB_API_TOKEN`
CI/CD variable (masked + protected), not `CI_JOB_TOKEN` -
`CI_JOB_TOKEN` reliably returns `404` on repository API endpoints
(branches/commits) even for this same project, a long-standing,
still-open GitLab platform limitation, not a settings issue. One-time
setup: **User Settings → Access Tokens** (Project Access Tokens are
disabled for this namespace, no self-service toggle - a **Personal
Access Token** is the practical substitute) → create a **fine-grained**
token (this namespace requires fine-grained over legacy PATs) scoped
to just this project, permissions **Code** (read), **Branch**
(create, read), **Commit** (create, read, update), **Merge Request**
(create, read, update) - nothing broader (in particular not
**Repository**, which manages whole repositories, nor Merge Request
merge/delete). Give it the longest expiry allowed and note the date - an
expired token fails the same way. Then Settings → CI/CD → Variables → add it as
`GITLAB_API_TOKEN`, ticked **Masked** and **Protected** (and make sure
the branch this runs against is a protected branch, or the
masked+protected variable won't be available to the job). Nothing
pushes to `main` with it any more (see the provisioning paragraph below),
so it needs no push permission.

Every resulting MR gets the same **review**: the observability
platform owner reviews and merges it - the deliberate human checkpoint.
GitLab's own formal "Approval rules" feature (require N approvals from
a specific group before merge) turned out not to be available on this
project's tier (Settings > Merge requests has no "Approval
rules"/eligible-approvers section - a GitLab Premium feature), so the
MR page correctly shows "Approval is optional" - not a bug, just means
no separate approve click is enforced. The actual checkpoint is
simpler and doesn't need that feature: `main` is a protected branch,
and this project has exactly one Maintainer/Owner (the observability
platform owner), so nobody else can click Merge at all - "nothing
merges without a human clicking merge" is already structurally
guaranteed by GitLab's normal permission model. The pipeline never
merges anything itself. Also enabled: **"Pipelines must succeed"**
under Merge checks (Settings > Merge requests) - blocks merging if
`validate:*`/`build:terraform-plan` failed.

And the same **provisioning + rollout**. [`scripts/provision.py`](scripts/provision.py)
reconciles **every** manifest (not just the one that changed, a full
idempotent recompute): per-tenant Mimir/Loki/Tempo/Pyroscope ingestion
limits (`helm/values/*-tenant-overrides.yaml`) and daily budgets
(`helm/values/ingestion-daily-budgets.yaml`), one dashboard per system
(`scripts/generate-system-dashboard.py`), one Grafana datasource
ConfigMap per tenant (`datasources/<tenant_id>.yaml`, a
`deleteDatasources` tombstone after offboarding), the per-tenant mTLS
CA/Issuer/client certificate (`tls-certs/`), and the gateway's tenant
allowlist (`collector-gateway/otel-gateway-collector.yaml`'s
`filter/reject_unknown_tenants` processor - see
[Multi-Tenancy](#b9-multi-tenancy-onboarding)). **Every** tenant is
included, 4087 (the platform itself) as well - no special-casing.

These generated files are part of the **merge request itself**: the
three `tenants:*-mr` jobs apply the manifest change to their checkout,
run `provision.py`, and commit the manifest and every generated change
in one commit ([`scripts/provisioning_sync.py`](scripts/provisioning_sync.py)),
so the reviewer sees exactly what will be rolled out. `provision:check`
(stage `validate`, merge request pipelines) fails if the committed files
don't match the manifests - for a hand-written MR, or one rebased onto a
newer `main`, run `python3 scripts/provision.py` and commit the result.
After the merge, `tenants:apply` (every push to `main` touching
`manifests/`) re-checks current `main` the same way (fail-closed: the
cluster never gets a state that isn't in git) and hands the files to
`tenants:rollout` in the same pipeline, which rolls them out to the live
cluster (`helm upgrade` + `terraform apply`). The pipeline pushes
nothing to `main`. Batching is free: merging several manifest MRs
applies all of them in one rollout. If two pipelines' jobs interleave, the
older one's `tenants:rollout` skips instead of putting an older `main`
back (newest wins, tracked in the `tenants-rollout-state` ConfigMap). Two MRs generated against the same
older `main` and merged back to back would leave `main` out of date -
`tenants:apply` then fails and lists the stale files; Settings > Merge
requests > **Merge commit with semi-linear history** prevents this by
requiring a rebase (and so a fresh `provision:check`) before merging.

### Onboarding

**Via the form**: leave the default "Onboard a new system" mode, fill
in System ID/Type/Name/Owner/Cost Center/Environments, submit. For
example, 4087 (the platform itself): System ID `4087`, Type
`Platform`, Name `Cloud Container Plattform`, Owner Team `Platform
Engineering`, Owner Contact `platform-team@example.com`, Cost Center
`CC-4087`, environment `prod` at size `L`.

**Via the API** (`$GITLAB_TOKEN`: your own personal access token, scope `api`) - the same 4087 request as above:

```bash
curl -X POST "https://gitlab.com/api/v4/projects/sre1541921%2Fobservability-otel-demo/pipeline" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "Content-Type: application/json" \
  --data @- <<'JSON'
{
  "ref": "main",
  "variables": [
    {"key": "SYSTEM_ID", "value": "4087"},
    {"key": "SYSTEM_TYPE", "value": "platform"},
    {"key": "SYSTEM_NAME", "value": "Cloud Container Plattform"},
    {"key": "OWNER_TEAM", "value": "Platform Engineering"},
    {"key": "OWNER_CONTACT", "value": "platform-team@example.com"},
    {"key": "COST_CENTER", "value": "CC-4087"},
    {"key": "DASHBOARD_TEMPLATE", "value": "platforms/platform-container.template.json"},
    {"key": "ENVIRONMENTS_JSON", "value": "[{\"env\":\"prod\",\"size\":\"L\"}]"}
  ]
}
JSON
```

Applications additionally need `variables[PLATFORM_REFS_JSON]` (a JSON
array of platform System IDs, e.g. `'["1286"]'`) - see
[`manifests/schema.json`](manifests/schema.json) for the full field
reference.

The `tenants:create-mr` job (see
[`scripts/create-onboarding-mr.py`](scripts/create-onboarding-mr.py))
turns the submitted fields into a manifest, validates it against [the
schema](manifests/schema.json), and opens an MR - one new file under
`manifests/platforms/` or `manifests/applications/`, nothing else
touched.

### Update

**Via the form**: switch to "Update an existing system" mode - only
System ID, Owner, and Environments & Ingestion Budget are
shown/editable, System ID/type/name aren't. For example, resizing
4087's `prod` budget from `L` to `M`.

**Via the API** - the same 4087 resize as an example:

```bash
curl -X POST "https://gitlab.com/api/v4/projects/sre1541921%2Fobservability-otel-demo/pipeline" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "Content-Type: application/json" \
  --data @- <<'JSON'
{
  "ref": "main",
  "variables": [
    {"key": "UPDATE_SYSTEM_ID", "value": "4087"},
    {"key": "OWNER_TEAM", "value": "Platform Engineering"},
    {"key": "OWNER_CONTACT", "value": "platform-team@example.com"},
    {"key": "ENVIRONMENTS_JSON", "value": "[{\"env\":\"prod\",\"size\":\"M\"}]"}
  ]
}
JSON
```

The `tenants:update-mr` job (see
[`scripts/create-update-mr.py`](scripts/create-update-mr.py)) - gated
on `$UPDATE_SYSTEM_ID` specifically, so the same request can only
ever start this job or `tenants:create-mr`/`tenants:offboarding-mr`,
never more than one - finds the existing manifest by System ID,
replaces only its `owner`/`environments` keys (carrying
`system_id`/`type`/`name`/`dashboard_template`/`demo_narrative`/
`platform_refs` over unchanged from the current file), and opens an MR
with an `update` commit action.

### Offboarding

**Via the form**: switch to "Offboard an existing system" mode, enter
the System ID, tick the confirmation checkbox, submit.

**Via the API** - offboarding 4722 (Spesenabrechnung) as an example:

```bash
curl -X POST "https://gitlab.com/api/v4/projects/sre1541921%2Fobservability-otel-demo/pipeline" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "Content-Type: application/json" \
  --data @- <<'JSON'
{
  "ref": "main",
  "variables": [
    {"key": "OFFBOARDING_SYSTEM_ID", "value": "4722"}
  ]
}
JSON
```

The `tenants:offboarding-mr` job (see
[`scripts/create-offboarding-mr.py`](scripts/create-offboarding-mr.py)) -
gated on `$OFFBOARDING_SYSTEM_ID` specifically, so the same request
can only ever start this job or `tenants:create-mr` above, never
both/neither - finds the existing manifest by System ID under
`manifests/{platforms,applications}/` and opens an MR that deletes it.
Once merged, the removal drops the tenant's ingestion-budget override,
deletes its dashboard file outright (`cleanup_orphaned_dashboards()` in
`scripts/provision.py` - unlike datasources, dashboard provisioning
already tracks file deletions on its own, so no tombstone is needed
here), rewrites its datasource ConfigMap to a `deleteDatasources`
tombstone (Grafana's datasource provisioning is add/update-only,
doesn't track deletions - see `_render_tombstone_configmap()`), and
drops its `tenant_id` out of the gateway allowlist regex.

What happens to the tenant's write paths and residual data (F14):

- **Write paths closed**: its gateway mTLS receiver, intermediate CA and
  namespace routes disappear (gateway and 4087 agent - logs from its
  former namespaces are dropped from then on), and its Pyroscope ingest
  credentials (`random_password.pyroscope_ingest`, iterated over the
  current tenants) and htpasswd entry are removed - the proxy rejects
  its pushes.
- **Residual data ages out on the global default retention**, not the
  tenant's former one: 10 days for Mimir and Pyroscope
  (`compactor_blocks_retention_period` / `limits.retention_period`, set
  explicitly - Mimir's own default would keep it forever, Pyroscope's
  31 days), 7 days for Loki, 48 hours for Tempo. Nothing is deleted
  immediately; a legal hold would need a different procedure (G11).

## Platform Features from the Requirements Review

Built for the gaps found against the ZOP requirements catalog (G02-G15;
G05, G07, G13 and G14 were dropped as out of scope for the demo).

### Masking (G02, FR-05)

The gateway's `transform/redact` processor masks e-mail addresses,
IBANs, AHV numbers, credit card numbers (by IIN prefix and length - OTTL
can't run a Luhn check), bearer tokens, credentials in URLs and
`password=`/`token:`-style assignments in every tenant's log bodies
(string bodies and the top-level values of structured bodies), log
attributes and span (event) attributes, before anything is stored.
Attributes whose *name* marks a credential (`password`, `api_key`,
`authorization`, `cookie`, ...) are deleted outright. Values nested
deeper than one level are not reached (OTTL's replace functions don't
recurse).
The catalog is `REDACTION_BASE` in `scripts/provision.py`; a system adds
its own rules in its manifest (`redaction.patterns`, RE2 regex, replaced
by `<redacted:NAME>`, checked for RE2 compatibility by
`validate-manifests` - example: 4721 masks the customer name in its
"Created customer" log line). Metrics are not masked - their attributes
are labels, which the Cardinality Rule keeps free of identifiers.
Test patterns: `scripts/testdata/redaction-samples.yaml`, run with
`scripts/test-redaction.py` (local, needs docker - runs the generated
processor in the gateway's own collector image).

### SLOs (G03, FR-10)

SLOs are OpenSLO v1 files under `slo/<tenant>/` (examples: 4721
Kundenverwaltung 99.5% successful operations, 4720 checkout 99%).
`scripts/generate-rules.py` converts them to OpenSLO v1alpha (the only
version Sloth reads), lets Sloth (v0.16.0, in the CI image) generate the
recording rules and adds multiwindow, multi-burn-rate alerts
(`SLOFastBurn` 14.4x/6x, `SLOSlowBurn` 3x/1x) plus `SLONoData`. The
result, `rules/<tenant>/slo.yaml`, is committed and loaded into the
Mimir ruler. **Missing data is never counted as success** (nor is zero
traffic, whose SLI is 0/0 = NaN): it fires
`SLONoData`, sets the system's status to "unknown" and lowers
`slo:data_coverage:ratio_30d`. Dashboard: *Operator: SLO Overview*
(pick the tenant's Mimir data source).

### Baselines, Anomalies and Calendar (G04, FR-06)

`rules/4721-prod/baseline.yaml` (hand-written, template for other
systems): Kundenverwaltung's throughput against the same hour of the
week over the last three weeks, read from the raw span metrics. Two
levels above and below the baseline (warning: max(30%, 2 stddev),
critical: max(60%, 4 stddev)) plus an absence alert. Lower bounds only
alert during business hours; nothing alerts in the maintenance window.
The calendar is a set of recording rules (`calendar:business_hours:bool`,
`calendar:maintenance_window:bool`, Europe/Zurich incl. DST). Tests:
`rules/4721-prod/tests/` (promtool unit tests and calendar cases at real
dates), run with `scripts/test-rules.py`.

### Mimir Ruler

G03, G04 and G08 run as Mimir ruler rules (enabled in
`helm/values/mimir-values.yaml`, container `mimir-ruler`, tenant
federation on). `rules/<tenant>/*.yaml` is loaded into namespace `repo`
of that tenant by `scripts/sync-mimir-rules.py` in `tenants:rollout`
(groups removed from the files are deleted, other namespaces are never
touched). There is no Mimir Alertmanager: ruler alerts show up in
Grafana's Alerting page as data-source-managed rules, without delivery.
`validate:rules` checks on every MR that `rules/` matches its sources
and passes promtool.

### Storage Showback (G06, FR-09)

The hourly `storage-usage` CronJob (`scripts/storage-usage.py`) lists
the four telemetry containers with a read/list-only SAS and pushes
`demo_storage_bytes{tenant, signal}` plus each tenant's showback budget
(`demo_storage_budget_bytes`, manifest size: S=5, M=50, L=125 GiB,
`SIZE_STORAGE_GB`). Pyroscope's not yet compacted multi-tenant segments
count as `unattributed`. Dashboard: *Operator: Storage Showback* (volume
per tenant and signal, % of budget, estimated monthly cost with an
adjustable CHF/GiB-month price). Showback only, nothing is enforced.

### Service Status (G08, FR-08)

Every tenant gets `rules/<tenant>/status.yaml`: `system:status:code`
0 functional, 1 degraded (slow SLO burn), 2 unknown (no telemetry for
10 minutes, or an SLO without SLI data), 3 disrupted (fast SLO burn). Business services and their
systems are defined in `services/business-services.yaml`; a federated
rule group in tenant `anonymous` computes `business_service:status:code`
as the worst member state (unknown ranks above degraded, a missing
member makes the service unknown). Dashboard: *Operator: Service Status*.

### Storage Tiering, Backup and Deletion (G10/G11, FR-17, NFR-14/15)

- **Tiering**: blobs in the four telemetry containers move to the Cool
  tier after 7 days without modification
  (`azurerm_storage_management_policy.observability`).
- **Protection**: blob versioning plus 7-day soft delete for blobs and
  containers; old versions are deleted after 7 days. No immutability
  policy on these containers - the compactors must delete blocks to
  enforce retention.
- **Restore** an accidentally deleted blob or container within 7 days:
  `az storage blob undelete` / `az storage container restore`, or
  promote an older version (`az storage blob copy start` from the
  version URL). Mimir/Loki/Tempo pick restored blocks up on their next
  bucket scan.
- **Deleting data of a tenant on request** (e.g. personal data in logs):
  Loki's delete API (`deletion_mode: filter-and-delete`):
  `POST /loki/api/v1/delete?query={...}&start=...&end=...` with
  `X-Scope-OrgID: <tenant>`; the compactor removes the lines after
  `retention_delete_delay` (2h). Traces, metrics and profiles have no
  selective delete in the OSS backends - they age out with the tenant's
  retention.
- **Legal hold**: not automated. A hold would copy the affected blocks
  into a separate container with an immutability policy - not on the
  live containers (see above).
- **Downsampling**: not available in Mimir OSS (no equivalent of Thanos
  downsampling); long-range queries read raw samples. Documented as a
  known limitation.

### Secrets (Key Vault) (G12, NFR-03)

The AKS add-on *Secrets Store CSI driver* with the Azure Key Vault
provider mounts secrets from the platform Key Vault
(`kv-otel-<suffix>`, access policies - the CI Service Principal may not
create role assignments) straight into pods, never into a Kubernetes
Secret. Mounted this way: Grafana's OpenClaw hook token and the
storage-usage SAS. Values are written write-only (`value_wo`): the hook
token (a CI/CD variable) is therefore not in the Terraform state at all.
The SAS still is - `azurerm_storage_account_sas` is a data source, whose
result Terraform always stores; it is read/list-only on the telemetry
blobs, rotated every 90 days, and the state itself is only readable
for project maintainers (GitLab-managed Terraform state). Still Kubernetes Secrets, and why: the
storage account key for Mimir/Loki/Tempo (passed by their Helm charts
into their own config Secrets) and Pyroscope (`pyroscope-storage`, env
expansion), OpenClaw's tokens (`openclaw-secrets`, environment
variables), the Pyroscope ingest credentials and the Postgres password -
each can move to a SecretProviderClass the same way when its consumer
supports file-based secrets.

### Budget Early Warning (G15, NFR-05)

`Tenant ingestion budget almost exhausted (>80% of daily budget)` in
`alerting/shared/operator-ingestion-budget.yaml`: per tenant and signal,
between 80 and 100% of the daily budget, before the enforcer throttles
at 100%. Visible in Grafana only (no mail in this demo).

## Scheduled Scans

`validate:python-deps` (pip-audit on the pinned Python requirements) and
`build:ci-image-scan` (trivy on the 4 ci-tools images) also run on a
pipeline schedule, so newly published vulnerabilities show up without a
change in this repo. One-time setup in the GitLab UI: Build → Pipeline
schedules → New schedule, target branch `main`, e.g. weekly. No other
job runs on a schedule. Dependency versions are bumped by hand.

## Demo

### Use Cases

Each use case ties platforms/applications together and demonstrates
specific observability disciplines. Redesigned down to 4 (from an
earlier 6, briefly 5) with three explicit goals: cover all three OTel
signal types where realistic, split cleanly between a Platform
Engineer audience and an Application Engineer audience (rather than
always blending platform+app into one use case), and demonstrate
multi-tenant ingestion budget enforcement, not just per-system
telemetry. UC4 (Object Storage Usage, 4015) was dropped outright
rather than replaced - 4015 stays onboarded and monitored, it just no
longer anchors a dedicated Use Case or alert - and the former UC5
(Multi-Tenancy: Ingestion Budget Enforcement) moved up to fill the
UC4 slot. The `Alerts` column pulls straight from
[`alerting/`](alerting/) - see that directory's own README for the
full rule definitions and the [Runbook](#runbook) below for how to
actually fire/clear each one live.

| # | Use Case | Systems Involved | Audience | Metrics | Logs | Traces | Alerts |
|---|---|---|---|---|---|---|---|
| UC1 | [Linux CPU Saturation](#uc1---linux-cpu-saturation) | 1286 | Platform Engineer | Host CPU metric - verified | — | — (pure infrastructure, no request context) | 1286 host CPU > 80% (1m) |
| UC2 | [Windows Service Crash](#uc2---windows-service-crash) | 1229 | Platform Engineer | — | Windows Event Log errors (Print Spooler crash, `detected_level=ERROR`) - verified | — (pure infrastructure, no request context) | 1229 Print Spooler service crashed (1m) |
| UC3 | [Kubernetes Microservices](#uc3---kubernetes-microservices) | 4720 | Application Engineer | — | — | Distributed traces across the checkout flow - verified (shipping service latency spike from `intlShippingSlowdown`, visible in Explore → Tempo and via a slow-request-count spanmetrics alert) | 4720 shipping requests > 500ms present (1m) |
| UC4 | [Multi-Tenancy: Ingestion Budget Enforcement](#uc4---multi-tenancy-ingestion-budget-enforcement) | cross-tenant (Operator view; `4711-prod` is this use case's own demo tenant, otherwise unrelated to it - see [Runbook](#runbook)) | Operator/SRE | Per-signal daily ingestion volume vs. each tenant's own signal-specific budget (`demo_ingestion_since_midnight`, `demo_ingestion_daily_budget`) - the same metrics the "Operator: Tenant Ingestion Budget" dashboard uses; enforcement (throttling, day-rollover) live-verified this session, including the demo break/fix flow itself | — | — | Tenant ingestion budget exhausted (>100% of daily budget) |

Systems no longer anchoring a use case of their own after this
redesign (1294, 4015, 4087, 4721, 4722) stay fully instrumented and
monitored in the fleet - they just don't get a dedicated presenter
walkthrough, and their own alert rules were removed (see
[`alerting/README.md`](alerting/README.md)) rather than kept around
unused.

### Runbook

For the presenter: how to actually run each Use Case live, end to end.
Every alert here evaluates every `interval: 1m` with a `for: 1m`
sustained-duration requirement, deliberately tuned short for a live
demo (see [`alerting/`](alerting/)) - the underlying PromQL rate
windows are `[1m]` too, not the more usual `[5m]`, so the metric
itself reflects a sudden load change within about a minute instead of
slowly ramping over five. Every break job takes **~1-2 minutes** to
visibly transition Normal → Pending → Firing on Grafana's own Alerting
page - confirmed live end to end on UC1 (Pending → Firing in 69s).
Every fix job clears its alert on the very next evaluation
(within ~1 minute).

**Set each dashboard's own time range to something narrow (e.g. "Last
15 minutes") before starting a break job** - found live: dashboard
panels use Grafana's `$__rate_interval` variable, which scales with
the *dashboard's currently selected time range*, not the fixed `[1m]`
window the alert rules themselves use. Left at a wide default range
(e.g. "Last 6 hours"), a 1-2 minute CPU/latency/error spike gets
smoothed into near-invisibility on the panel even though the alert
itself fires correctly off its own, narrower window - confirmed live
(the same query showing 100% over `[1m]` showed only ~50% over
`[30m]`, and would be far flatter still over a 6h-scaled interval).
The alert firing is unaffected either way; this is purely about the
panel staying visually convincing during a live demo.

Apps to have open:

| App | System ID | URL |
|---|---|---|
| OTel Astronomy Shop Demo | 4720 | https://astronomy-shop.sre.fs167.ch/ |
| Kundenverwaltung | 4721 | https://kundenverwaltung.sre.fs167.ch/customers (REST API, no root page - also `/health`) |
| Spesenabrechnung | 4722 | `http://<vm-windows-demo public IP>:8080/expenses` (REST API, no root page - also `/health`; IP via `az vm show -g rg-bensc-001 -n vm-windows-demo -d --query publicIps -o tsv`) - not its own Use Case anymore, no longer UC4's demo tenant either (see UC4's own Runbook entry) |

Mitarbeiterverzeichnis (4711, on `vm-rocky-demo`) has no dedicated step
below - UC1 is 1286 (the platform) only now, no app to open.

#### UC1 - Linux CPU Saturation

1. Show 1286's own dashboard (`Grafana → Dashboards → 1286 → Linux
   Basis`, `env` dropdown defaults to `PROD`), point out the CPU panel.
2. Run **`demo:uc1-break`** - starts 2 CPU-spin loops on
   `vm-rocky-demo` (its 2 vCPUs).
3. Watch the CPU panel climb; after ~1-2 min, **"1286 Linux Basis -
   host CPU > 80%"** fires on the Alerting page.
4. Run **`demo:uc1-fix`** - kills the loops. CPU drops immediately;
   the alert clears on its next evaluation.

#### UC2 - Windows Service Crash

1. Show 1229's own dashboard (`Grafana → Dashboards → 1229 → Windows
   Server Basis`), point out the **Windows Event Log: Error** panel
   and **Recent Logs** below it - that's what this UC's alert watches.
2. Run **`demo:uc2-break`** - starts a loop on `vm-windows-demo` that
   kills the Print Spooler service's process every 30s, so it keeps
   crashing and restarting.
3. After ~1-2 min, **"1229 Windows Server Basis - Print Spooler
   service crashed"** fires; the Error panel and Recent Logs both show
   repeated Service Control Manager error events.
4. Run **`demo:uc2-fix`** - stops the loop; Spooler stabilizes, and
   the alert clears once no new errors appear within its lookback
   window (~2 min).

#### UC3 - Kubernetes Microservices

1. As a customer, open the real shop (https://astronomy-shop.sre.fs167.ch/),
   add an item to the cart and check out with a non-US shipping
   address - note it completes quickly.
2. Run **`demo:uc3-break`** - flips the shop's own `flagd` feature
   flag `intlShippingSlowdown` from `off` to `5sec` (the chart's own
   official fault-injection mechanism, not something this repo
   builds), then restarts `flagd` itself - found live: despite its
   own `fsnotify` file watcher, this deployment's `flagd` doesn't
   actually pick up a ConfigMap content change without a restart (its
   config volume looks seeded once at pod start, not a live mount).
3. Repeat the same checkout - "the customer reports the site is
   slow": the shipping step now visibly hangs for ~5s.
4. In Grafana, open the Astronomy Shop dashboard's **Recent Traces**
   panel (or Explore → Tempo, datasource `tempo-4720-prod`, query
   `{resource.service.name="shipping" && duration > 1s}`) and find a
   checkout trace with it - a long `shipping` span shows exactly where
   the delay is. On the dashboard's **Request Latency (p95) by
   Endpoint/Operation** panel, filter/look for the **`POST
   /ship-order`** series specifically - that's the one span_name that
   actually spikes (~4.1s p95 while broken), every other series on
   that panel stays fast throughout.
5. Check Grafana's Alerting page: **"4720 OTel Astronomy Shop Demo -
   shipping requests slow"** fires within ~1-2 min, same ballpark as
   this repo's other Use Cases. This rule counts actual slow requests
   rather than computing a percentile - found live that a p95-based
   query (an earlier version of this rule) was structurally unable to
   register the problem reliably, since `intlShippingSlowdown` only
   ever affects international-address checkouts, a minority of the
   shop's overall traffic; a percentile query gets diluted back to
   "normal" the moment any of the majority of unaffected (US-address)
   requests lands as the most recent sample. Counting instead of
   percentile-ing fixes this: every slow request registers and stays
   counted for a full 3-minute window regardless of how much fast
   traffic happens alongside it.
6. Run **`demo:uc3-fix`** - flips the flag back to `off` and restarts
   `flagd` the same way.
7. Verify from both sides: the same checkout is fast again, Tempo's
   new traces show a normal-length shipping span, and the alert clears
   within ~3 min once your own slow checkout ages out of the rule's
   3-minute counting window (assuming no other slow checkout lands in
   the meantime).

#### UC4 - Multi-Tenancy: Ingestion Budget Enforcement

1. Show the "Operator: Tenant Ingestion Budget" dashboard (`Grafana →
   Dashboards → shared`) - explain per-tenant daily budgets and this
   being an Operator/SRE-facing, cross-tenant view rather than one
   system's own dashboard.
2. Run **`demo:uc4-break`** - floods Mitarbeiterverzeichnis's
   (`4711-prod`) Loki ingestion for ~2.5 minutes
   (`scripts/demo-uc4-flood.py`), enough to push its Loki daily usage
   past its own actual 1 GiB/day (S-tier) Loki budget - each signal has
   its own independent daily budget now (NFR-05), so this flood only
   throttles 4711-prod's Loki traffic, not its Mimir/Tempo/Pyroscope
   traffic too. This is possible quickly now that the per-second rate
   limit is generic and size-independent - unlike the old size-tied
   design, where any tenant's fastest possible fill time was a fixed
   ~4.8h regardless of size (found live before this redesign).
3. Allow up to ~2 more minutes after the flood - the daily-budget
   enforcer only checks every 2 minutes (not a real-time gate the way
   the per-second rate limit is, so some overshoot past 100% before it
   catches up is expected and normal). Once it does, **"Tenant/signal
   has used up its daily ingestion budget"** fires for `4711-prod`'s
   `loki` signal specifically, and the `ingestion-midnight-snapshot`
   enforcer throttles `4711-prod`'s rate/burst limit to near-zero on
   Loki's runtime ConfigMap ONLY - its Mimir/Tempo/Pyroscope traffic
   keeps flowing unaffected (NFR-05: each signal is its own independent
   budget now, see the "Budget enforcement" section above) - visible as
   real discards on the dashboard's Loki Discard Rate panel only.
4. Run **`demo:uc4-fix`** - un-throttles `4711-prod` on every signal
   it's currently throttled on (just Loki, in this walkthrough) and
   resets its daily usage back to 0% on all four signals immediately (a
   one-off in-cluster Job running the enforcer script's own
   `--reset-tenant` mode), without waiting for the next real midnight
   rollover. The alert clears on its next evaluation.

A real midnight rollover (not exercised by `demo:uc4-fix`, which is a
manual shortcut for demo pacing) restores every currently-throttled
tenant the same way, automatically, once a day.

## Destroy

### Infrastructure & Observability Stack (Pipeline)

**GitHub Actions:** Actions → *Destroy* → Run workflow → scope
`everything`, type `destroy` into the confirm field. The workflow runs the
same order as below (aiops → fleets + tenants → observability stack →
infra).

**GitLab CI:** set the CI/CD variable `CONFIRM_DESTROY=yes`, then start
the manual jobs in the `destroy` stage, in order:

0. **`destroy:aiops`**: removes the OpenClaw remediation agent. Run it
   first - it is not a `needs` of the later jobs, so nothing enforces
   the order, but its resources live on the cluster `destroy:infra`
   deletes.
1. **The six fleet-teardown `destroy:*` jobs** (one per underlying VM/namespace) and
   **`destroy:tenants`**: the fleet-teardown jobs tear down the two demo VMs
   (including their NICs/public IPs/NSGs/OS disks - each VM's job also
   covers whatever's staged on top of it, e.g.
   `destroy:1286-linux-basis` also removes 4711) and the
   Kubernetes-based apps (Astronomy Shop, Kundenverwaltung -
   `destroy:4721-kundenverwaltung` also removes its dedicated
   PostgreSQL database - SNMP simulator, Filestorage - including its
   Storage Account). `destroy:tenants` tears
   down every onboarded tenant's own datasource/dashboard ConfigMaps and
   the gateway `OpenTelemetryCollector` CR. All seven are independent -
   run whichever ones you need, in any order (among themselves).
2. **`destroy:observability-stack`**: tears down the LGTM+P stack + collectors (Helm
   releases, `observability`/`opentelemetry-operator-system` namespaces).
   `needs` all six fleet-teardown `destroy:*` jobs **and** `destroy:tenants`
   (`optional: true`, but since they always exist in the pipeline they
   still gate this job in practice - it won't show as playable until all
   seven have run). `destroy:tenants` specifically must go first, not
   just conveniently before: its gateway CR's `null_resource` shells out
   to `kubectl delete opentelemetrycollector` on destroy, which needs the
   `OpenTelemetryCollector` CRD schema this job's own Helm release
   installs to still be present.
3. **`destroy:infra`** (deliberately last): tears down the AKS cluster
   and network - the DNS zone stays untouched (see
   [A2](#a2-create-dns-zone--cloudflare-ns-delegation)), no fresh
   Cloudflare NS delegation needed on the next `deploy:infra`. `needs`
   `destroy:observability-stack` the same way.

Afterwards, set `CONFIRM_DESTROY` back to `no`/remove it, to avoid
accidental destruction on future runs.

The observability stack's Key Vault is only **soft-deleted**
(`purge_soft_delete_on_destroy = false`): purging needs a
subscription-level permission the pipeline identities don't have. It
expires after 7 days and doesn't block a rebuild - the next deploy
creates a vault with a new random name.

`az resource list -g rg-bensc-001 -o table` after a full cleanup
(all `destroy:*` jobs run) should show only the DNS zone and `aks-vnet`
(one-time bootstrap resources, see
[A2](#a2-create-dns-zone--cloudflare-ns-delegation)/[A5](#a5-create-aks-vnet--grant-ci-sp-role-assignment) -
neither is touched by `destroy:infra`).

### Cleaning Up the DNS Zone + Delegation (Manual)

Only relevant if the DNS zone is no longer needed permanently - in the
normal destroy/deploy cycle it deliberately stays in place (see
[A2](#a2-create-dns-zone--cloudflare-ns-delegation)):

```bash
az network dns zone delete -g $RESOURCE_GROUP -n sre.fs167.ch
```

At your main DNS provider (e.g. Cloudflare), also delete the 4 NS entries
for the `sre` subdomain that were created in
[A2](#a2-create-dns-zone--cloudflare-ns-delegation).

## Known Pitfalls

- **A `deploy:infra` that reimages nodes (e.g. enabling Calico) can
  fail with `failed calling webhook "pod-eviction-observability.grafana.com"
  ... no endpoints available for service "mimir-rollout-operator"`** -
  found live: the rollout-operator's eviction webhook (`failurePolicy:
  Fail`, guarding the zone-aware PDBs) was briefly unreachable while
  the operator's own single pod was being moved off a draining node,
  and AKS aborted the upgrade (cluster `provisioningState: Failed`,
  half the nodes done). Simply re-run `deploy:infra`: it resumes the
  remaining nodes. If the cluster still shows `Failed` afterwards,
  `az aks update -g rg-bensc-001 -n aks-otel-demo --yes` reconciles
  it. Not fixable by config: the chart pins the operator to 1 replica
  (not HA by design), and `failurePolicy: Ignore` would let a drain
  take out two ingester zones at once.
- **VM collectors kept sending into a dead connection after a node
  reimage** - found live: `vm-rocky-demo`'s gRPC connection via the
  internal Azure LB died silently when the node carrying its flow was
  reimaged; without keepalive the collector never noticed, every
  metrics export hit `DeadlineExceeded` and tenant 1286's metrics
  dashboards went empty until `otelcol-contrib` was restarted. Fixed
  with gRPC keepalive on the VMs' `otlp/host` exporter
  (`instrumentation/platforms/{1286-linux,1229-windows}-basis/config.yaml`)
  and a matching keepalive enforcement policy on the Gateway's tenant
  receivers (`scripts/provision.py`). Takes effect on a VM once its
  config is rolled out again by the platform pipeline.
- **`tenants:apply` and `tenants:rollout` used to run in two separate
  pipelines instead of one** - `tenants:apply`'s own script does a
  `git commit` + `git push` mid-job (to persist the generated
  Mimir/Loki overrides, datasources, gateway allowlist, and dashboards
  in git); that push spins up a brand-new second GitLab pipeline.
  `tenants:rollout` only ever auto-ran in *that* second pipeline (via
  the commit-author check documented in the entries above) - meaning
  the original, merge-triggered pipeline never got past `tenants:apply`,
  and the live-cluster rollout happened one pipeline later than a human
  watching would expect. Found live while walking through the full
  onboarding flow end to end. Fixed by having `tenants:apply` upload
  its generated files as a short-lived `artifacts:` block and
  `tenants:rollout` pull them via `needs:` plus a rule matching
  `tenants:apply`'s own `changes: manifests/**/*` condition exactly -
  both jobs now get created together, in the same pipeline, whenever a
  manifest change lands on `main`. No trigger-token/pipeline-variable
  path involved (still the same security property as before). The
  bot's own follow-up push still exists (git still needs somewhere to
  push to for durability), but no longer even spins up its own
  pipeline at all - found live, still redundant even after this fix:
  the push landed a `validate:yaml` run that had nothing left to check
  (the real rollout already happened) and a spurious manual
  `tenants:rollout` button. Fixed with GitLab's own `git push -o
  ci.skip` push option on that one commit (see `tenants:apply`'s own
  comment) - purpose-built for exactly this "this push shouldn't
  trigger CI at all" case, cleaner than a `$CI_COMMIT_AUTHOR`-based
  `workflow:` exclusion would have been. The `destroy:*` bot-author
  exclusions (next entry) stay in place regardless, as a
  belt-and-suspenders fallback. **Superseded:** the bot push is gone
  entirely - the generated files are committed in the merge request
  itself and `tenants:apply` only verifies them (see
  [Processes](#processes)); the `destroy:*` bot-author exclusions were
  removed with it.
- **`destroy:*` jobs were clickable on every push to `main`, including
  an onboarding MR merge and `tenants:apply`'s own automated commit** -
  not the intended "manual safety valve for a genuine human/infra push"
  behavior (see this file's own top-of-file comment on why they
  deliberately have no `changes:` filter). Fixed by adding two narrow
  `when: never` exclusions ahead of the existing catch-all in all 6
  rule-block locations: a push authored by the bot (requires
  `$CI_PIPELINE_SOURCE == "push"` alongside the author check, same
  reasoning as `tenants:rollout`'s own bot-check - without it this
  would also hide destroy on a `web` "complete start" pipeline any time
  `main`'s tip happens to still be the bot's last commit), and any push
  touching `manifests/**/*`. A genuine human/infra push untouched by
  either falls through to the unchanged catch-all. (The bot-author
  exclusion was removed again once the bot push itself was gone - only
  the `manifests/**/*` one remains.)
- **`validate:manifests`/`validate:yaml` didn't run on the trigger
  pipeline that opens an onboarding/update/offboarding MR** - only on
  `push`/`web`, so the very first pipeline a self-service request goes
  through skipped both sanity checks. Added a
  `$CI_PIPELINE_SOURCE == "trigger" && ($SYSTEM_ID || $UPDATE_SYSTEM_ID
  || $OFFBOARDING_SYSTEM_ID)` rule branch to both (no `changes:` filter
  - a trigger-sourced pipeline has no real push event to diff against,
  so it would evaluate unconditionally true anyway, same finding as
  elsewhere in this file).
- **The `onboarding` stage/job-name prefix stopped making sense once
  the same jobs started handling update and offboard requests too** -
  found live, pointed out directly, while offboarding a system: a job
  named `onboarding:apply` running to *remove* a tenant reads as
  actively wrong, not just imprecise. Renamed the stage to `tenants`
  and all six jobs in it to match this repo's own `<stage>:<name>`
  convention: `onboarding:create-mr`/`update-mr`/`offboarding-mr` →
  `tenants:create-mr`/`update-mr`/`offboarding-mr`, `onboarding:apply`
  → `tenants:apply`, `onboarding:tenants` → `tenants:rollout` (not
  `tenants:tenants`). `validate:onboarding-manifests` renamed to
  `validate:manifests` for the same reason (it validates every
  manifest, not just onboarding ones). `pages` stays `pages` (the one
  pre-existing, documented exception to the naming convention -
  GitLab's own requirement, not a style choice).
- **`validate:yaml` had the same class of gap a third time** - its
  directory list (`helm/ kubernetes/ instrumentation/ ansible/ manifests/`)
  missed `examples/*.yaml` entirely (6 files, all genuinely missing
  `---` once actually checked) and, less obviously, `.gitlab-ci.yml`
  itself - which turned up a real finding too (also missing `---`).
  Switched to scanning the whole repo (`yamllint .`) instead of an
  explicit directory list, with `.onboarding-staging/` excluded via
  yamllint's own `ignore:` config key at the time - a deliberate
  temporary holding area for manifests not yet run through the
  self-service demo, not permanent repo content worth linting. That
  directory (and the `ignore:` entry for it) was later removed
  entirely once every staged system had been restored into
  `manifests/` for real.
- **`validate:shell`'s `shellcheck examples/tomcat-demo-app/*.sh` had
  the same class of gap as `validate:python`'s own `scripts/*.py`-only
  glob (see below)** - found by asking the same "does this really check
  the whole repo?" question a second time. Missed
  `terraform/environments/demo/init.sh` and
  `ansible/roles/middleware-tomcat/files/tomcat-traffic-generator.sh`
  entirely, in any pipeline, ever - both passed cleanly once actually
  checked (no hidden finding this time, unlike the Python one). Fixed
  with `find . -name "*.sh" -not -path "./.git/*" -exec shellcheck {}
  +` instead of the directory-scoped glob, plus widened `changes:`
  filters to `**/*.sh`.
- **`validate:python`'s `ruff check scripts/*.py` only ever covered
  `scripts/` itself** - a non-recursive, single-directory glob, so
  `instrumentation/platforms/object-storage/workload.py` (the only
  other `.py` file in this repo) silently never got linted, in any
  pipeline, ever - found
  live only by asking whether the job really checks "every Python
  script in the repo" and then actually checking. Turned up one real,
  previously-invisible finding once run against it: `EXE001` (a shebang
  present on a file that isn't executable). Fixed both: `chmod +x` on
  the file, and `ruff check .` (whole repo) instead of the
  `scripts/`-only glob, so a future `.py` file anywhere else can't slip
  through the same way again.
- **"Ansible is being run in a world writable directory... ignoring it
  as an ansible.cfg source"** - GitLab's docker executor checks out the
  repo world-writable, so Ansible (a security check on its own side,
  unrelated to any project setting) refuses to load
  `ansible/ansible.cfg` from it at all, in every job that runs
  `ansible-lint`/`ansible-playbook`. No config setting can suppress the
  warning - it fires before config is even loaded. Fixed at the source:
  `chmod o-w ansible` before invoking Ansible, in `validate:ansible` and
  `.install_ansible` (covers every `deploy-instrumentations:*` job).
  Not purely cosmetic: once the file actually loads, its own
  `[ssh_connection] pipelining = True` becomes live for the first time
  too (previously dormant) - a real, deliberate performance change for
  the Linux instrumentation jobs, not just quieter logs.
- **`tenants:rollout`'s commit-author auto-run rule matched an
  unrelated trigger pipeline** - it checks *whatever commit currently
  happens to be `main`'s tip*, not "did a new commit just land". Found
  live: submitting an offboarding request while `tenants:apply`'s
  own commit was still `main`'s HEAD (no newer commit since) made this
  rule match too, auto-running `tenants:rollout` on a pipeline that
  had nothing to do with it. Same root-cause family as the other
  trigger-source bugs above - fixed by requiring `$CI_PIPELINE_SOURCE
  == "push"` in this rule too, not just the author check alone (a
  `trigger`-sourced pipeline is never itself the "new commit landed"
  event this rule means to catch, even when the author happens to
  match). This whole commit-author-based auto-run mechanism was later
  removed entirely - see the "two separate pipelines" entry further
  below for why and what replaced it.
- **Every `destroy:*` job showed up as an available manual button on
  every onboarding/offboarding form submission's own trigger
  pipeline** - their `rules:` (the deliberate "always available, no
  `changes:` filter" exception, see this file's own top-of-file
  comment) only ever checked `$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`,
  with no pipeline-source restriction at all - true for a trigger
  pipeline against `ref=main` same as a real push. Found live, pointed
  out directly: a routine form submission's pipeline listed every
  `destroy:*` job (infra, observability-stack, every fleet, tenants) as
  clickable, `when: manual` or not. Fixed by adding `&&
  $CI_PIPELINE_SOURCE != "trigger"` to the six places this rule is
  defined (`.destroy_fleet`, `destroy:1286-linux-basis`,
  `destroy:1229-windows-basis`, `destroy:tenants`,
  `destroy:observability-stack`, `destroy:infra`) - still always
  available on a genuine push or a manual "complete start" (`web`), just
  not on a public-token trigger call anymore.
- **Tried the textbook Terraform CI best practice - `build:terraform-plan`
  saves `terraform plan -out=tfplan` as an artifact, `deploy:infra`
  pulls it via `needs:` and runs `terraform apply tfplan` against that
  exact plan - and hit a real, documented incompatibility with this
  repo's backend.** Terraform's `http` backend embeds the
  `-backend-config` credentials (including the password) *inside the
  saved plan file itself*. This repo's backend auth uses
  `$CI_JOB_TOKEN`, which is per-job and ephemeral - valid only for the
  job that generated it. So the plan file `build:terraform-plan`
  produced carried *that job's* (already-expired) token, and
  `deploy:infra`'s own `terraform apply tfplan` failed acquiring the
  state lock with `Error: Error acquiring the state lock / HTTP remote
  state endpoint requires auth`, even though `deploy:infra` had just
  run its own successful `terraform init` with its own valid token
  moments earlier - the saved plan doesn't use that fresh
  re-initialization for its own lock/apply calls. Documented upstream:
  [hashicorp/terraform#28294](https://github.com/hashicorp/terraform/issues/28294),
  [gitlab-org/gitlab#346075](https://gitlab.com/gitlab-org/gitlab/-/issues/346075).
  The real fix would be a long-lived credential (e.g. a Project Access
  Token) for backend auth instead of `$CI_JOB_TOKEN` - but that trades
  `$CI_JOB_TOKEN`'s naturally ephemeral, per-job scope for a
  standing credential with Terraform state write access, not justified
  here just to get plan/apply artifact-passing working. Reverted:
  `build:terraform-plan` and `deploy:infra` are back to two fully
  independent `terraform init`/plan-or-apply cycles, each with its own
  `$CI_JOB_TOKEN`.
- **`build:terraform-plan` failed on the very first onboarding MR's own
  pipeline** with `could not parse Azure CLI version: launching Azure
  CLI: exec: "az": executable file not found in $PATH` - looked
  Azure-CLI-related, but the real cause: GitLab withholds protected
  CI/CD variables (`AZURE_CLIENT_ID` etc., all marked Protected) from a
  merge request pipeline unless *both* the source and target branch are
  protected - an onboarding/offboarding branch never is. With
  `ARM_CLIENT_ID` etc. silently empty, the `azurerm` provider falls
  back to Azure CLI auth, which fails outright since the
  `hashicorp/terraform` image has no `az` binary at all. First fix
  attempt - scoping the `merge_request_event` rule with the same
  `changes:` filter the push rule already has - turned out incomplete:
  **a merge request pipeline runs its source branch's own
  `.gitlab-ci.yml`, not the target branch's**, so an MR/branch already
  open when the `changes:` fix landed on `main` kept hitting the
  original bug regardless (found live, the very next pipeline re-run on
  that same MR). This surfaced the real question: this repo has no
  workflow that actually opens an MR touching `terraform/` at all -
  infra changes are always committed straight to `main` by hand, and
  the only MRs ever generated here are onboarding/offboarding ones,
  which only ever touch `manifests/`. So the `merge_request_event` rule
  served no real purpose in the first place - removed entirely, rather
  than filtered, once that became clear. `validate:*`'s own
  `merge_request_event` rules don't have this credential problem
  (nothing they run needs Azure access) - but on reflection, given this
  repo's only real MR workflow is onboarding/offboarding (manifests/
  only), running all five unconditionally meant three of them
  (`validate:shell`/`python`/`ansible`) were guaranteed no-ops on every
  single MR. Scoped those with the same `changes:` filter their push
  rules already have too, for consistency and to stop wasting CI time -
  no functional loss, since they'd still fire correctly whenever their
  own paths are actually touched (including for onboarding MRs, where
  only `validate:yaml`/`validate:manifests` are ever
  relevant anyway).
- **`deploy:observability-stack` had a leftover, completely
  unconditional `if: $CI_PIPELINE_SOURCE == "trigger", when: on_success`
  rule** - a real privilege-escalation bug, worse than the one already
  documented below: unlike that one (which at least required a caller
  to know/guess a marker variable name), this rule needed nothing but
  the already-public trigger token `form/index.html` embeds - **any**
  trigger-API call against this project, including every single
  legitimate onboarding/offboarding form submission, auto-ran a full
  `terraform apply` against the live observability stack, no review, no
  `SYSTEM_ID` check, nothing. Found live: an onboarding form submission
  (a routine `tenants:create-mr` trigger call) also silently started
  `deploy:observability-stack` in the same pipeline. Traced via `git
  log -S` to a leftover rule from an even earlier design than the one
  described below (predating the Terraform migration) that was
  apparently never removed when `tenants:rollout`'s own analogous
  marker-variable rule was found and fixed. `deploy:observability-stack`
  has no legitimate reason to auto-trigger at all (unlike
  `tenants:rollout`, which needs *some* auto-trigger path after
  `tenants:apply`'s commit) - fixed by deleting the rule outright,
  leaving only the two genuinely-manual `web`/`push` rules. **General
  lesson, worth re-checking periodically**: `grep -n
  '\$CI_PIPELINE_SOURCE == "trigger"' .gitlab-ci.yml` should only ever
  show the `workflow:` block and the two conditionally-gated
  `tenants:create-mr`/`tenants:offboarding-mr` rules - any other
  match is this same bug recurring.
- **PyYAML's default dumper doesn't indent list items under their
  parent mapping key** (`environments:\n- env: prod`, dash at column 0
  instead of indented two spaces under the key) - valid YAML, but
  `validate:yaml`'s yamllint flagged it as a real indentation error on
  the very first generated onboarding manifest, blocking that MR's
  pipeline. `create-onboarding-mr.py`'s `yaml.safe_dump()` produced
  this by default; fixed with the standard PyYAML workaround (a
  `SafeDumper` subclass overriding `increase_indent` to force
  `indentless=False`).
- **A merge request created via the GitLab API sometimes doesn't get a
  pipeline on its own - but explicitly forcing one is worse** -
  `create-onboarding-mr.py`/`create-offboarding-mr.py` create the
  branch, then the commit, then the MR (in that order), all as separate
  back-to-back API calls rather than a normal git push. Found live on
  the very first real onboarding MR: it sat at "Pipelines: 0",
  permanently blocked by the "Pipelines must succeed" merge check -
  fixed by explicitly calling `POST /merge_requests/:iid/pipelines`
  right after creating the MR. **Found live again, one MR later**: that
  explicit call itself failed with `405 Method Not Allowed`, because
  GitLab *had* already auto-started a pipeline for that one on its own
  - made the call best-effort (catch and log the 405, don't fail the
  script) to handle both cases. **Found live a third time, the very
  next offboarding MR**: with the explicit call now succeeding *and*
  GitLab's own auto-trigger also firing, the MR ended up with two
  separate, genuinely duplicate pipelines for the same commit. GitLab's
  own auto-trigger behavior turned out to be the inconsistent one, not
  a bug worth working around at all - removed the explicit call
  entirely. Trusting GitLab's default is the lesser problem either way:
  a rare missing pipeline needs one manual "Run pipeline" click; a
  duplicate silently wastes CI minutes on every single request.
- **`rules: changes:` always evaluates true for a pipeline with no real
  git push event** (trigger-API pipelines, scheduled/tag pipelines) -
  GitLab has no diff to compare against in that case. Found live:
  submitting the onboarding form (a `trigger`-sourced pipeline, no
  actual push) made every single `changes:`-gated job across the
  *entire* pipeline appear, including all of `validate:*` and (harmless
  here, since nothing in `manifests/` had actually changed)
  `tenants:apply` - not just the intended `tenants:create-mr`.
  Fixed by adding `$CI_PIPELINE_SOURCE == "push"` to every
  `changes:`-gated rule's own `if:`, so it only applies to pipelines
  where GitLab can compute a real diff - GitLab's own documented fix
  for this exact gotcha.
- **GitLab's "Minimum role to use pipeline variables" project setting
  (Settings > CI/CD > Variables) blocks the onboarding form's trigger
  call entirely if set to "No one allowed"** - found live, the very
  first real form submission: `variables[SYSTEM_ID]=...` etc. failed
  with `{"message":{"base":["Insufficient permissions to set pipeline
  variables"]}}` (HTTP 400), since a pipeline trigger token's
  permissions are deliberately limited for exactly the public-exposure
  reason this project already relies on (see the trigger-token
  discussion above) - but that also means it needs an explicit minimum
  role low enough to actually pass `variables[...]`. Set to
  **Developer** (the least restrictive of the three real role options)
  - doesn't weaken this design's actual security property, since the
  trigger token can still only ever start `tenants:create-mr`/
  `tenants:offboarding-mr`, both of which just open an MR that
  still needs human review. A required one-time setup step, now part
  of [Processes](#processes)'s manual GitLab setup.
- **`form/index.html`'s error handler concatenated GitLab's JSON error
  `message` field directly into HTML without checking its type** -
  GitLab sometimes returns a *nested object* for `message` (like the
  pipeline-variables error above), not a plain string; string-
  concatenating an object in JavaScript silently produces the literal
  text `[object Object]` instead of the actual error, exactly what
  showed up in the browser on that first failed submission attempt.
  Fixed by only using `message` directly when it's already a string,
  and `JSON.stringify()`-ing it (or the whole response body) otherwise,
  so the real GitLab error always reaches the user.
- **A `#` in the generated Windows admin password silently broke the
  Ansible WinRM connection, with a completely misleading error** - the
  `deploy-fleets:4722-spesenabrechnung`/`deploy-instrumentations:1229-windows-basis`
  jobs kept failing with `[ERROR]: Task failed: Unable to execute ssh
  command line on a controller: [Errno 2] No such file or directory:
  b'ssh'` on the very first `ansible.windows.win_*` task - misleading,
  since these jobs never use SSH at all (Windows targets connect over
  WinRM). Root-caused by reproducing locally
  (`ansible-inventory --list` against a hand-built inventory line):
  `.gitlab-ci.yml`'s `cat > ansible/inventory/generated.ini << EOF`
  heredocs embed `terraform ... output -raw admin_password` unquoted,
  on the same line as `ansible_connection=winrm ansible_winrm_transport=...` -
  and `#` starts a comment in Ansible's INI inventory parser, silently
  truncating everything after it on that line whenever the randomly
  generated password happened to contain one. Without
  `ansible_connection=winrm` actually reaching Ansible, it fell back to
  its own default connection type (`ssh`) - which isn't even installed
  in these Windows-only job containers, hence the confusing error.
  Fixed at the source: `random_password.windows_admin`
  (`terraform/modules/client-vm/main.tf`) no longer allows `#` in its
  `override_special` set. **A password generated before this fix stays
  in Terraform state unchanged** - `random_password` doesn't regenerate
  just because its config changed, so an already-existing Windows VM
  needs a fresh `destroy:1229-windows-basis` + redeploy (not just a
  config push) before this actually takes effect on it.
- **A GitLab `rules:` item with no `when:` defaults to `when:
  on_success` (i.e. auto-run), not `when: manual`** - found live: every
  manual-intended job's `rules:` has an `if: '$CI_PIPELINE_SOURCE ==
  "web"'` branch ahead of its `changes:`-filtered one, meant only to
  make the job *available* on a manually-started "complete start"
  pipeline (see this file's own top-of-file comment) - but that branch
  didn't itself carry `when: manual`, so it defaulted to auto-run
  instead of just appearing for a manual click. `deploy:infra` (and, it
  turned out, every other manual-intended job sharing this same
  two-rule pattern - `deploy:observability-stack`, `tenants:rollout`'s
  own manual-fallback rule, and all 18 `deploy-fleets:*`/
  `deploy-instrumentations:*` jobs) auto-started the moment a "Run
  pipeline" was triggered, well before the intended manual-click gate.
  Fixed by adding `when: manual` (and `allow_failure: true`, matching
  the push-triggered rule right below it) to that `web`-source branch on
  all 21 affected jobs. `validate:*`/`build:terraform-plan`/`pages`/
  `tenants:apply` are correctly unaffected - those are meant to run
  unattended on a "complete start" too, not gated behind a manual click.
- **GitLab pipeline trigger tokens don't restrict which variables a
  caller may pass, only that a pipeline can start at all** - found
  live while setting up self-service onboarding's auto-rollout: the
  first design had `tenants:apply` (after committing a generated
  onboarding change) call this project's own pipeline trigger API with
  a marker variable (`AUTO_DEPLOY_TENANTS=true`), which
  `tenants:rollout`'s `rules:` checked to auto-run the actual rollout.
  This looked reasonably scoped (only `tenants:apply` was expected to
  ever set that variable) but wasn't: the *same* trigger token
  `form/index.html` embeds client-side for the self-service form -
  necessarily public, readable in the page source, the same exposure
  model as a Stripe publishable key - is valid for starting *any*
  pipeline on this project with *any* variables, not just the ones a
  given caller "should" set. Anyone who read that token out of the
  page could have called
  `curl --form token=<the public token> --form "variables[AUTO_DEPLOY_TENANTS]=true" .../trigger/pipeline`
  directly and rolled a real `helm upgrade`/`terraform apply` out to
  the live cluster, skipping the MR review step entirely - a real
  privilege-escalation path, not a theoretical one. Fixed before ever
  being deployed live: `tenants:rollout` now auto-runs by checking the
  **commit author** instead (`$CI_COMMIT_AUTHOR` on a plain
  `$CI_PIPELINE_SOURCE == "push"` pipeline) - only `tenants:apply`'s
  own push, authenticated with the server-side-only `GITLAB_API_TOKEN`
  that never reaches a browser, can ever produce a `main` commit
  authored by the fixed bot identity the rule checks for. General
  lesson for this repo: a pipeline trigger token is safe to expose
  client-side only for jobs whose own `rules:` gate on something a
  public caller can't forge (a specific required variable being
  present, e.g. `$SYSTEM_ID` for `tenants:create-mr`) - never safe to
  use, directly or indirectly, as the *sole* gate for anything that
  actually changes the live cluster. The commit-author check itself was
  later replaced too (see the "two separate pipelines" entry below) -
  not because it was insecure (it wasn't), but because it only ever
  matched in a second, separately-triggered pipeline, splitting
  `tenants:apply`/`tenants:rollout` across two pipeline runs instead of
  one.
- **Dashboard files never got cleaned up when a manifest disappeared**,
  unlike datasources - found live while manually staging all 14
  manifests out of `manifests/{platforms,applications}/` to reset the
  repo to a "nothing onboarded" state for an E2E demo, worked around by
  hand with `git rm` at the time. Root cause: `scripts/provision.py`'s
  `regenerate_dashboards()` only ever adds/updates
  (`generate-system-dashboard.py` writes one JSON file per manifest, but
  nothing ever removed the file for a manifest that's since gone).
  Grafana's *datasource* provisioning has the same add/update-only
  limitation, already handled correctly via a `deleteDatasources`
  tombstone ConfigMap (see `_render_tombstone_configmap()`) - but its
  *dashboard* provisioning is different: it already tracks file
  deletions on its own, so the actual fix for dashboards is simpler,
  just delete the file. Fixed via a new `cleanup_orphaned_dashboards()`
  in `scripts/provision.py`, called from `main()` right after
  `regenerate_dashboards()`: for each `dashboards/{prod,eng,at}/`,
  match each file's leading `<system_id>-` (its filenames are always
  `<system_id>-<slug>.json`, written by `generate-system-dashboard.py`)
  against the System IDs of currently-manifested tenants for that
  environment, and delete any file whose ID isn't among them. Needed by
  the self-service offboarding milestone above (a merged
  offboarding MR leaves exactly this situation - manifest gone,
  dashboard file still on disk) but also fixes the same latent gap for
  any other manifest removal, including the manual staging done for the
  E2E demo.
- **The gateway's tenant-rejection filter (`attributes/tag_tenant` +
  `filter/reject_unknown_tenants`) caused two live outages before the
  real bug was found**: first, the allowlist regex's
  `re.escape()`-produced `\-` isn't valid inside an OTTL string literal
  ("invalid quoted string"), so the collector failed to start at all -
  fixed by dropping the escaping (tenant IDs are always `[a-z0-9-]`,
  nothing regex-special, so none was needed). Second, after that fix,
  the collector started but dropped **100%** of all metrics and logs
  (confirmed: `otelcol_receiver_accepted_*` exactly equaled
  `otelcol_processor_filter_*_filtered`) - the actual bug: the
  `attributesprocessor` (`attributes/tag_tenant`) writes to each
  span/log_record/datapoint's own attribute map, never to
  resource-level attributes ("The attributes processor modifies
  attributes of a span, log, or metric" - confirmed against that
  processor's own README), but the filter condition checked
  `resource.attributes["tenant_id"]`, which the processor never
  populated - every item hit the `== nil` branch and got dropped. Fixed
  by checking `attributes["tenant_id"]` (the signal's own attribute map)
  instead. Neither failure mode was catchable by
  `validate:yaml`/`validate:shell` (both are collector-runtime errors, not
  syntax errors) - verified this time with a real OTLP client sending
  one span/metric/log per signal type with a known-good and a
  deliberately fake `tenant_id`, confirming via
  `otelcol_processor_filter_*_filtered` deltas that only the fake one
  was dropped in each case, before rolling out to all three pipelines.
  **Any future change to this file needs the same live test against a
  real collector before merging** - a `kubectl apply` succeeding is not
  sufficient evidence.

- **Moving a resource with a destroy-time `provisioner` between
  Terraform states doesn't actually run that provisioner** - found live
  moving `null_resource.otel_gateway_collector` from
  `observability-stack-crs` to `../tenants` (moving the gateway
  allowlist to `tenants:rollout`'s scope): the apply that removed
  the resource block from `observability-stack-crs`'s config logged
  `null_resource.otel_gateway_collector: Destruction complete after 0s`
  with **no** `Provisioning with 'local-exec'...`/`Executing: [...]`
  lines at all (compare the sibling `mimir_webhook_cleanup` resource's
  apply-time provisioner in the same log, which does show them) - the
  underlying `kubectl delete opentelemetrycollector` never actually
  ran. This is documented Terraform behavior, not a bug: destroy-time
  provisioners only run when a resource is destroyed via `terraform
  destroy` (or an apply that destroys it while its resource block,
  provisioner included, is still present in configuration) - when a
  resource block is deleted from the `.tf` file entirely, Terraform has
  no config left to read the provisioner from, so it silently skips it
  and just drops the resource from state. Harmless in this specific
  case (the gateway CR/pods kept running unchanged - actually a nice
  zero-downtime side effect - and the new location's `kubectl apply`
  cleanly adopted the still-live object once `tenants:rollout` ran), but
  worth knowing for any future "move a resource with a destroy-time
  provisioner between states" migration in this repo: it needs an
  explicit `terraform destroy -target=<resource>` while the resource
  block still exists, as a separate step before removing it from
  config, if the destroy-time side effect actually needs to run.
  `destroy:tenants`'s own copy of this same provisioner is unaffected -
  a real `terraform destroy` (not a config removal) always has the
  resource block, and its provisioner, still present in config at
  destroy time.
- **Also found in the same migration: dropping a provider from
  `required_providers` entirely, while a state still has a now-config-
  removed resource of that provider's type, breaks decoding that
  resource's prior state** - `local_sensitive_file.kubeconfig` in
  `observability-stack-crs` hit `Warning: Missing resource schema from
  provider... No resource schema found for local_sensitive_file when
  decoding prior state` after its `required_providers.local` entry was
  removed alongside the resource itself: with no version constraint at
  all, Terraform installed an unconstrained "latest" `local` provider
  (`2.9.0`) that apparently can't decode a state entry written by the
  older locked version, leaving it stuck in state instead of being
  cleanly destroyed (that resource is missing from the `1 destroyed`
  count in that apply's summary). Fixed by keeping the same pinned
  `required_providers.local` entry (`~> 2.5`) even though no resource in
  the module's config uses it anymore, purely so a subsequent apply can
  decode and finally destroy the orphaned entry - removable once
  `terraform state list` confirms it's actually gone.

- **`grafana.sre.fs167.ch` can serve Traefik's own default self-signed
  cert ("TRAEFIK DEFAULT CERT") instead of a real one** - not a config
  bug, but Let's Encrypt's **production rate limit**: max 5 certificates
  per exact hostname per 168h. This repo's destroy/rebuild testing
  cycle requests a fresh cert for the same hostname every time, so
  repeated same-day rebuilds can exhaust that quota - when it does,
  `cert-manager`'s `Certificate` order errors out (`429 ... too many
  certificates (5) already issued for this exact set of identifiers`),
  `grafana-tls-secret` never gets created, and Traefik falls back to
  its built-in default cert for any host with no matching TLS secret.
  Self-resolves once the 168h window rolls forward (the error message
  itself states the exact retry time) - `cert-manager` retries
  automatically, no action needed. For a same-day fix, temporarily
  pointing `ClusterIssuer` `letsencrypt-azuredns` at Let's Encrypt's
  staging endpoint (unlimited quota, but not browser-trusted) is the
  practical workaround.
- **One over-budget tenant's dropped metrics can take down an
  unrelated tenant's dashboard too** - found live: the "1295
  Applicationserver Apache Tomcat" dashboard's JVM Threads panel (and
  every other JVM panel) went empty (`1295-prod` was Tomcat's own
  tenant at the time - since merged into `4711-prod`, see "Middleware/
  runtime tenants" under [Multi-Tenancy](#b9-multi-tenancy-onboarding), but
  the incident and its root cause below are unrelated to that merge).
  Root cause was `1286-prod`
  (vm-rocky-demo's own host-metrics tenant, not 1295 at all): its
  `hostmetrics` receiver had a `processes` scraper enabled (one full
  metric set per running process on the host - ~130 processes on that
  VM), pushing 2500-3300+ samples per 30s scrape against a 1185
  `ingestion_burst_size` budget the dashboard never even used any
  `process_*` metrics from in the first place. The gateway's
  `prometheusremotewriteexporter` got HTTP 429s
  (`err-mimir-tenant-max-ingestion-rate`) from Mimir, retried, still
  failed, and dropped the batch (`Dropping data`, thousands of
  `dropped_items` per occurrence) - and because the gateway batches
  multiple tenants' data through the same export queue, a persistently
  failing 1286-prod batch created backpressure that also delayed/
  dropped 1295-prod's (unrelated) JVM metrics riding along from the
  same VM. Fixed by removing the `processes` scraper from the Linux
  platform template (now `instrumentation/platforms/1286-linux-basis/config.yaml`, was
  `clients/otel-collector-linux-rocky.yaml` at the time - renamed
  twice since, first splitting platform vs. middleware templates into
  their own directories, then folding `clients/` into
  `instrumentation/`) entirely (unbounded, unused cardinality - see
  that file's own comment) - confirmed live:
  after restarting `otelcol-contrib` on the VM to pick up the new
  config, the gateway's 429s stopped within about a minute. Metrics
  still didn't resume immediately, though - restarting the local
  collector had broken the OTel Java agent's existing OTLP connection
  to it (a **second**, independent effect of the same restart), which
  needed `systemctl restart tomcat` on the VM to force the agent to
  reconnect fresh before data flowed again. **Lesson**: check for
  unused, high-cardinality scrapers/receivers before assuming a missing
  metric is a query or dashboard problem - and after restarting a local
  collector any client already connected to it, re-check that the
  client's own connection actually recovered rather than assuming it
  auto-reconnected.
- **A vendored Grafana-community dashboard's `$datasource` variable had
  no default, so it silently showed no data since the day it was
  imported**: `shared/otel-collector-15983.json`
  ([grafana.com #15983](https://grafana.com/grafana/dashboards/15983/))
  has a `type: "datasource"` variable matching any Prometheus datasource,
  with an empty `current`. With 48 Prometheus datasources now
  provisioned, Grafana resolves that to whichever one it picks first -
  in practice the generic `Mimir` (`isDefault: true`, pinned to
  `4087-prod`). This dashboard's own metrics (`otelcol_*`) are
  self-scraped and land under the `anonymous` tenant instead (same
  convention as every other self-monitoring panel here), so every panel
  had nothing to show regardless of which tenant-scoped datasource
  Grafana happened to land on. Fixed by restricting the variable's
  `regex` to `/^Mimir-anonymous$/` - only one option left, so it's the
  only one Grafana can pick, and nobody can accidentally re-break it by
  picking a tenant-scoped datasource from the dropdown. Worth checking
  any other vendored dashboard for the same unset-datasource-variable
  pattern before assuming "no data" means a real telemetry gap.
- **Grafana's `helm upgrade` deadlocked the first time a change actually
  touched the pod template** (adding `sidecar.datasources`, needed for
  the `tenants:rollout` split): default `RollingUpdate` + a `ReadWriteOnce`
  PVC + a single replica is a standing trap - the new pod can't attach
  the volume while the old one still holds it, and Kubernetes won't kill
  the old one until the new one is ready, so neither ever happens.
  `kubectl get pods` showed the new pod stuck at `Init:0/1` with a
  `FailedAttachVolume` / `Multi-Attach error` event indefinitely. Fixed
  with `deploymentStrategy.type: Recreate` in `grafana-values.yaml`
  (kills the old pod first, no PVC contention) - would have hit on any
  future change to Grafana's pod template, not just this one, so worth
  keeping even though this specific upgrade is done.
- **Grafana's `traces` panel type silently renders zero rows for very
  fast (sub-millisecond) traces**: found live on 4711's dashboard - the
  panel's own Query Inspector showed the backend response genuinely
  containing 20 traces, yet nothing rendered. Root cause: Tempo's search
  API omits the `durationMs` summary field for very fast traces (this
  demo's simplest HelloWorld-servlet-speed requests, ~0.2-0.6ms), and
  the `traces` panel type appears to require that field to render a row
  at all - even though the trace's actual data (ID, root service, root
  name, start time) is present and fetching the full trace by ID works
  fine. Every "Recent Traces" panel across every dashboard template now
  uses `type: "table"` with `tableType: "traces"` on the target instead
  of `type: "traces"` - same underlying data, immune to the missing
  field, just a plainer visual than the purpose-built trace list.
- **`kubeletstats` receiver's default `metric_groups` doesn't include
  PVC/volume usage at all**: `[container, pod, node]` (the DaemonSet
  agent's original setting) never produces any `k8s.volume.*` metric,
  so nothing tracked the LGTM stack's own persistent storage (Mimir/
  Loki/Tempo/Grafana/Kafka PVCs) anywhere. Adding `volume` to
  `metric_groups` fixes that, but the resulting metrics carry no
  volume-*type* label to distinguish a real PVC-backed volume from a
  ConfigMap/Secret/projected-token/emptyDir volume sharing the same
  metric shape - found live: `k8s_volume_name: "storage"` is a real PVC
  on `mimir-ingester` but an `emptyDir` on `mimir-distributor`. Built
  the resulting dashboard panel's filter as an explicit pod-name +
  volume-name allowlist cross-checked against `kubectl get pvc -n
  observability`, not a guess from the label names alone - see
  `platform-container.template.json`'s "Persistent Volume Usage" panel.
- **A VM client's local `otlp` receiver being wired into the `traces`
  pipeline doesn't mean its `logs` are going anywhere**: found twice,
  independently, on both VM clients (Tomcat/4711, Spesenabrechnung/4722
  - at the time this was found, both apps still relayed through the
  platform's local collector; both now push straight to the gateway
  instead (their own middleware template, not the platform's), so this
  specific failure mode no longer applies, though the underlying lesson
  - a receiver wired into one pipeline says nothing about any other -
  still does) - each app's own OTel SDK/agent was correctly
  configured to export logs via OTLP (`OTEL_LOGS_EXPORTER=otlp` on the
  Java side once flipped from the original `none`; `.NET`'s
  `builder.Logging.AddOpenTelemetry(...)` was always on), but the local
  collector's `otlp` receiver was only referenced by the `traces`
  pipeline - a receiver not referenced by a `logs` pipeline just drops
  the logs signal silently, no error anywhere. Fixed by adding a
  `logs/app` pipeline on both VMs (`receivers: [otlp]`, same tenant/
  exporter as the traces pipeline) - a receiver needs an explicit
  pipeline per signal type it should actually carry, not just per
  signal type it happens to receive.
- **Mimir returns empty results for an aggregation over a short
  `rate()` window on high-cardinality metrics, even though the bare
  `rate()` and a longer window both work fine**: found live on 1295's
  JVM dashboard - `sum by (...) (rate(jvm_gc_duration_seconds_sum[...]))`
  returned nothing when Grafana's `$__rate_interval` resolved to a short
  window (`1m15s` at a 1-minute step), while the same query with a fixed
  `5m`/`10m` window worked, and the bare unaggregated `rate()` worked at
  any window size. Looks like a Mimir query-sharding edge case
  triggered by this tenant's unusually large label set (full JVM
  command line, classpath, etc. via `resource_to_telemetry_conversion`).
  Every panel combining an aggregation with `rate()` on JVM metrics now
  uses a fixed `5m` window instead of `$__rate_interval` - see
  `jvm-middleware.template.json`'s panel descriptions for the live
  before/after evidence.
- **Every application's container logs landed under the platform's own
  tenant (4087-prod), not their own**: the DaemonSet agent
  (`instrumentation/platforms/4087-container-platform/config.yaml`) reads every pod's
  container logs on the node it runs on via `filelog`, and its single
  `otlp/gateway` exporter has one fixed `tenant_id: "4087-prod"` header
  - correct for the agent's own host/kubelet metrics (it does serve the
  whole node, not one application), wrong for logs, which belong to
  whichever tenant actually owns that pod. Found live while reviewing
  4139 (PostgreSQL)'s dashboard: real postgres container logs existed
  (`k8s_container_name: postgres`), just entirely under 4087-prod
  instead of 4139-prod. Fixed with a `routing` connector on the `logs`
  pipeline: the filelog receiver's `container` operator already
  extracts real `k8s.namespace.name`/`k8s.container.name` resource
  attributes from the kubelet log file path (no k8sattributes processor
  needed for this, unlike at the gateway), so the connector routes on
  those to one exporter per known namespace (or, for postgres
  specifically, per container name, since it shares a namespace with
  the Kundenverwaltung app it serves) - each exporter has its own fixed
  tenant_id, same pattern as the VM clients' `otlp/host`/`otlp/app`
  split. Anything unmatched (platform namespaces, and any future
  namespace not yet added to the routing table) falls through to the
  default pipeline, preserving today's correct behavior for genuine
  platform infrastructure logs. Verified live for all 5 routed
  destinations (filestorage-demo, netzwerk-demo, astronomy-shop,
  postgres container -> 4139-prod) with fresh log lines actually
  arriving under the right tenant; the 5th (kundenverwaltung app ->
  4721-prod) initially couldn't be confirmed since that app hadn't
  logged anything since its own startup - turned out its background
  traffic generator thread had silently stalled (see the Known Risks /
  Follow-ups entry above), and once restarted, real log lines
  confirmed flowing to 4721-prod too. The postgres-specific
  `k8s.container.name == "postgres"` routing rule was later removed
  again once 4139 folded into 4721's own tenant (see Multi-Tenancy's
  "Middleware/runtime tenants" note) - postgres already runs in the
  `kundenverwaltung` namespace, so it now falls through to the existing
  namespace-level rule and reports `tenant_id: 4721-prod` like the rest
  of the app, without needing its own dedicated table entry.
- **Loki `deploymentMode: Distributed` validation error**: `backend`,
  `read`, `write` must be explicitly set to `replicas: 0` - already
  included in `helm/values/loki-values.yaml`.
- **Mimir Helm upgrade conflict on webhooks**: repeated installs can
  collide with stale webhook configs -
  `terraform/environments/observability-stack/main.tf`'s
  `null_resource.mimir_webhook_cleanup` cleans these up automatically
  before every Mimir install.
- **OTel Operator without cert-manager**: self-signed certs are enabled
  in the `opentelemetry_operator` `helm_release`
  (`admissionWebhooks.autoGenerateCert.enabled=true`), since cert-manager
  isn't assumed to be present yet at the time the operator is installed
  ([B2](#b2-lgtmp-stack--otel-collectors)) - independent of
  cert-manager being used for Grafana in
  [B3](#b3-install-traefik--cert-manager)-[B5](#b5-grafana-ingress--datasources).
- **The `loki` exporter no longer exists**: newer Collector Contrib
  builds use `otlphttp` against Loki's native OTLP endpoint
  (`/otlp/v1/logs`) instead of a dedicated `loki` exporter.
- **"entry too far behind" in Loki**: on first startup, the filelog
  receiver reads old log lines (`start_at: beginning`) that fall outside
  Loki's default acceptance window. Solved for the demo with
  `reject_old_samples: false`.
- **RBAC for the `k8sattributes` processor**: the operator doesn't
  automatically create cluster-wide read permissions on pods/namespaces -
  `terraform/environments/observability-stack/main.tf`'s
  `kubernetes_cluster_role.otel_collector_k8sattributes`/
  `_cluster_role_binding` add that (native Terraform resources today;
  originally a plain `kubernetes/collectors/otel-collector-rbac.yaml`
  applied via `kubectl`, migrated and deleted once redundant - see
  the "Hand-maintained 'reference' copies silently drift" entry below
  for the general pattern this was an instance of).
- **Tempo "too many unhealthy instances" on search**: the
  `tempo-distributed` chart expects a replication factor of 3 for the
  ingester ring by default, which doesn't fit a single-replica demo. Fix:
  set
  `tempo.structuredConfig.ingester.lifecycler.ring.replication_factor: 1`
  in `helm/values/tempo-values.yaml` (NOT as the top-level
  `replicationFactor` - the chart ignores that path).
- **OTel demo chart: naming collisions on Grafana/Prometheus/Jaeger**:
  the `opentelemetry-demo` chart bundles its own subcharts for Grafana,
  Prometheus, Jaeger, OpenSearch, which collide with the existing stack.
  Fix: `grafana.enabled=false`, `prometheus.enabled=false`,
  `jaeger.enabled=false`, `opensearch.enabled=false` in
  `helm/values/otel-demo-values.yaml`.
- **OTel demo chart: patching the bundled collector's pipeline is a
  dead end** - the chart bundles its own `opentelemetry-collector`
  subchart, and two things go wrong trying to keep it and redirect its
  export pipeline to our own gateway: patching individual values via
  `--set` creates duplicate `OTEL_EXPORTER_OTLP_ENDPOINT` entries, and
  overriding `service.pipelines.*.processors`/`exporters` without
  fully carrying over every referenced processor/connector (Helm
  replaces arrays entirely, it doesn't merge them) breaks startup with
  "references processor X which is not configured". Both go away by
  disabling the bundled collector entirely instead
  (`opentelemetry-collector.enabled: false` in
  `helm/values/otel-demo-values.yaml`) and redirecting each already
  OTel-SDK-instrumented microservice straight at the gateway with a
  single `OTEL_COLLECTOR_NAME` `envOverrides` entry in
  `instrumentation/applications/4720-otel-astronomy-shop/values-instrument.yaml`
  - every service already builds its OTLP endpoint from that one
  variable, so no per-service `--set` and no custom pipeline is needed
  at all.
- **Hand-maintained "reference" copies silently drift from what's
  actually live**: found repeatedly while collapsing instrumentation
  config duplication onto a single source under `instrumentation/`.
  `ansible/roles/{platform-linux,platform-windows}/templates/*.j2`
  never received this schema's new resource attributes even after
  `schema/core.yaml` was adopted - only the separate
  `instrumentation/platforms/{linux,windows}/config.yaml` "reference"
  got them, since nothing kept the two in sync.
  `ansible/roles/middleware-tomcat/templates/tomcat.service.j2` had a
  live, running bug from the same cause:
  `OTEL_RESOURCE_ATTRIBUTES=service.namespace=linux-agent,deployment.environment=demo`
  - `linux-agent` was the *platform's* own namespace value copy-pasted
  into the *application's* config, and `demo` isn't a valid
  `eng|at|prod` value. Worst case: the hand-runnable
  `setup-tomcat.sh`/`instrument-tomcat.sh` reference scripts once kept
  alongside the Tomcat Ansible role for readability carried this exact
  same stale `OTEL_RESOURCE_ATTRIBUTES` line, undetected until the
  role itself was fixed and the two were compared side by side - a
  reference nobody re-derives from is a reference that silently stops
  being one. Fix, applied repo-wide: collapse every such pair into one
  canonical file that's also what actually gets deployed live -
  Ansible/Terraform reference `instrumentation/`'s files directly
  (`{{ role_path }}`/`file()`) instead of keeping a role-local or
  example-local mirror; `setup-tomcat.sh`/`instrument-tomcat.sh` were
  deleted outright rather than fixed, since
  `ansible/roles/middleware-tomcat/` already fully reimplements every
  step they performed and a third, doc-only copy was exactly the kind
  of thing that drifts.
- **Host metrics without a `job`/`instance` label**: without an explicit
  `service.name`/`service.namespace` in the agent DaemonSet's `resource`
  processor, the `prometheusremotewrite` exporter produces no
  `job`/`instance` labels for host metrics - leaving dashboard variables
  (templated on those labels) empty, even though the raw data arrives in
  Mimir. Fix in `instrumentation/platforms/4087-container-platform/config.yaml`: add
  `service.namespace`/`service.name` in the `resource` processor; do NOT
  apply `resourcedetection` to the metrics pipeline on the gateway
  (otherwise it overwrites the host attributes set by the agent with the
  gateway pod's own attributes).
- **Grafana links internally to the wrong URL**: without setting
  `grafana.ini.server.root_url`, Grafana keeps using
  `localhost`/the cluster-internal address internally for links, sharing,
  OAuth callbacks etc., even though it's reachable externally via TLS
  ingress. The values file
  [`helm/values/grafana-values.yaml`](helm/values/grafana-values.yaml),
  used in [B5](#b5-grafana-ingress--datasources), sets this
  correctly.
- **Linux agent (systemd) crashes with "error creating AttrProc"**:
  systemd services don't automatically inherit shell environment
  variables - `${env:HOSTNAME}` in `instrumentation/platforms/1286-linux-basis/config.yaml`
  stays empty without an explicit systemd override. Fix: set
  `Environment=HOSTNAME=%H` via `systemctl edit`/a drop-in file, then
  `daemon-reload` and restart.
- **journald receiver: "No journal files were opened due to insufficient
  permissions"**: the `otelcol-contrib` service runs under its own,
  non-root system user without read access to `/var/log/journal`. Fix:
  `sudo usermod -aG systemd-journal otelcol-contrib`, then restart the
  service.
- **OTel Operator webhook: "x509: certificate signed by unknown
  authority"**: the OTel Operator generates a new self-signed certificate
  for its admission webhook
  (`admissionWebhooks.autoGenerateCert`) on every Helm install/upgrade
  (`observability-stack`'s `opentelemetry_operator` `helm_release`). If
  an OpenTelemetryCollector resource is applied right afterwards, that
  can briefly fail until the operator pod has loaded the new
  certificate. Originally fixed with retry/backoff (`apply_with_retry`,
  up to 8 attempts at 10s each) in the old `scripts/deploy-collectors.sh`
  - `kubernetes_manifest` (`observability-stack-crs`, applying the
  collector CRs) has no equivalent built-in retry, but in practice the
  gap this raced against is now much wider: the operator install is
  followed by grafana/traefik/cert-manager finishing their own installs
  in the same `observability-stack` apply, then a second, separate
  `terraform init`/`apply` for `observability-stack-crs` - real elapsed
  time the single-pass shell script never had. If it recurs anyway,
  re-running `deploy:observability-stack` picks up where the failed
  apply left off (same as any other transient Terraform apply failure).
- **Cluster capacity wasn't enough for the LGTM stack + collectors + the
  full Astronomy Shop demo at the same time**: 3x `Standard_D4s_v5`
  (12 vCPU/48GB minus AKS system overhead) hit their limit once all ~24
  shop microservices run as well - individual pods (including a
  post-upgrade hook) then stayed `Pending` permanently, and Helm
  upgrades could fail with "post-upgrade hooks failed: timed out
  waiting for the condition". Fixed by scaling out, not up:
  `aks_node_count` in `terraform/environments/demo/variables.tf` is now
  `5` (was 3) - `kubenet`'s `max_pods: 30`/node turned out to be the
  actual binding constraint, not raw CPU/memory, so more smaller nodes
  fit the workload better than fewer bigger ones. Confirmed live with
  all 12 demo systems plus the full shop deployed simultaneously.
  Hit again with 5 nodes when the Key Vault Secrets Store CSI add-on (G12,
  2 DaemonSet pods per node) and the Mimir ruler were added: all 150 pod
  slots taken, otel-gateway-collector and Mimir kafka/ingester `Pending`
  ("Too many pods"), the Mimir helm upgrade timed out. Now `6` nodes.
  Raised to `7` with Tempo 3 (block-builder, live-store, backend
  scheduler/worker and its own Kafka broker instead of ingester and
  compactor: 3 more pods) - 6 nodes left 10 free slots of 180, too few
  for the parallel Loki/Tempo/Grafana rollouts and their surge pods.
- **GitLab CI: unplayed manual jobs block later stages/jobs**: `rules:`-based
  `when: manual` jobs default to `allow_failure: false`, meaning an
  unplayed `deploy:infra` blocks the `deploy` stage's other jobs (and an
  unplayed `deploy:observability-stack`/`destroy:observability-stack` blocks the stage after
  it). Fix: all manual jobs in `.gitlab-ci.yml` explicitly have
  `allow_failure: true`; the `deploy:observability-stack`/`deploy-fleets:*` jobs
  additionally use `needs: [{job: ..., optional: true}]` so they can each
  be run standalone without the job(s) before them having run in the
  same pipeline.
- **`hashicorp/terraform` Docker image**: `ENTRYPOINT` is fixed to
  `terraform`, so GitLab's shell invocation gets interpreted as a
  Terraform subcommand ("Terraform has no command named 'sh'"). Fix:
  `image: name: ..., entrypoint: [""]` in `.gitlab-ci.yml`.
- **`mcr.microsoft.com/azure-cli` image is minimal (Azure Linux/Mariner)**:
  has neither `tar` nor `awk` (package name `gawk`) pre-installed, which
  `get-helm-3` needs for the Helm binary and its checksum verification.
  `.install_tools` in `.gitlab-ci.yml` installs both with a fallback
  across `apt`/`tdnf`/`dnf`/`apk`, whichever is available in the given
  image.
- **Azure AD Graph API restricted in playground/sandbox tenants**: direct
  `azuread_application`/`azuread_service_principal` Terraform resources
  fail with `403 ... must be in the local tenant`, and delete operations
  on application objects generally fail with `403 Insufficient
  privileges` (even for self-created apps). `az ad sp create-for-rbac`
  works reliably (a different code path) - which is why both bootstrap
  service principals
  ([A3](#a3-create-the-gitlab-ci-service-principal),
  [A6](#a6-create-the-cert-manager-service-principal)) are deliberately
  created via a direct, documented `az` command instead of declarative
  `azuread_*` Terraform resources or a Terraform wrapper around them
  (which would only wrap the same command via `local-exec` anyway).
  Empirically confirmed: even `az ad sp create-for-rbac` itself fails
  with `Insufficient privileges to complete the operation` when run under
  the identity of a **service principal** instead of a human, delegated
  user login (tested with the CI service principal, which has Azure RBAC
  Contributor on the Resource Group) - Azure RBAC roles don't grant Azure
  AD Graph permissions. The
  [A6](#a6-create-the-cert-manager-service-principal) step therefore
  can't be moved into the pipeline as long as it runs under a pure
  service-principal identity instead of a delegated user session - stays
  permanently manual.
- **DNS zone deliberately kept out of Terraform**: originally the DNS
  zone was part of `modules/networking` and got destroyed along with
  every `destroy:infra` - forcing a fresh, slow Cloudflare NS
  delegation (minutes to ~1h propagation) on every rebuild, just to end
  up with the same subdomain again. The zone is now created manually,
  once ([A2](#a2-create-dns-zone--cloudflare-ns-delegation)), and only
  referenced from `modules/networking` via `data "azurerm_dns_zone"` - as
  a side effect, this also lets
  [A6](#a6-create-the-cert-manager-service-principal) (cert-manager SP,
  needs the zone ID) run right after A3/A4, instead of only after the
  first `deploy:infra`.
- **`kubeletstats` receiver failing with `403 Forbidden` since it was
  introduced**: `kubernetes/collectors/otel-collector-rbac.yaml` (since
  migrated to native `kubernetes_cluster_role*` Terraform resources in
  `terraform/environments/observability-stack/main.tf`, and deleted)
  only bound its `ClusterRole` to the `otel-gateway-collector` ServiceAccount -
  the agent DaemonSet's `otel-agent-collector` ServiceAccount (the one
  that actually runs the `kubeletstats` receiver, calling the kubelet's
  `/stats/summary` endpoint directly) had no RBAC grant at all. Result:
  every pod/container/node-level Kubernetes metric (`k8s_pod_*`,
  `k8s_node_*`) was silently missing from Mimir since day one - only
  `system_*` host-level metrics (from `hostmetrics`, unaffected) ever
  showed up. Azure RBAC/Contributor has no bearing on this - it's a pure
  in-cluster Kubernetes RBAC check the kubelet performs against the
  caller's ServiceAccount. Fixed with a dedicated `ClusterRole`/
  `ClusterRoleBinding` granting `nodes/stats: get` to
  `otel-agent-collector`.
- **Container log parser set to `format: crio`, but AKS runs containerd**:
  `instrumentation/platforms/4087-container-platform/config.yaml`'s `filelog` receiver
  used the `container` operator with `format: crio`, which fails to parse
  almost every log line on a containerd node ("regex pattern does not
  match"). Combined with the RBAC issue above, this meant cluster logs
  outside a handful of lucky edge cases never reliably reached Loki.
  Fixed by setting `format: containerd`.
- **No self-monitoring metrics for the OTel Collectors themselves**: the
  collectors expose their own internal metrics on `:8888/metrics`
  (`otelcol_*` - receiver/processor/exporter throughput, process health),
  but nothing scraped that endpoint, so Mimir never had any `otelcol_*`
  data and the "OpenTelemetry Collector" dashboard (15983) would have
  been completely empty. Fixed by adding a `prometheus/self` receiver
  (self-scrape of `localhost:8888`) in a **separate** metrics pipeline in
  both the agent and gateway configs - deliberately not routed through
  the agent's shared `resource` processor, which unconditionally
  overwrites `service.name`/`service.namespace` to
  `node-hostmetrics`/`agent` and would otherwise destroy the
  `job`/`service.name` identity (`otelcol-contrib`) the dashboard's `$job`
  variable depends on.
- **Fixing the RBAC/format bugs above surfaced a log-ingestion backlog
  problem**: once cluster-wide container logs actually started parsing
  correctly, the sudden volume (every node re-reading
  `/var/log/containers/*.log` from the beginning on every collector
  restart, since the `filelog` receiver had no persistent checkpoint)
  exceeded Loki's default ingestion-rate and gRPC message-size limits
  (`429`/`503` responses, visible as `Exporting failed` retries in the
  collector logs). Two fixes:
  - Raised `limits_config.ingestion_rate_mb`/`ingestion_burst_size_mb`
    and `server.grpc_server_max_recv_msg_size` in
    `helm/values/loki-values.yaml`, so a burst doesn't get rate-limited
    in the first place.
  - Added a `file_storage` extension to `otel-agent-daemonset.yaml`
    (`filelog.storage: file_storage`) backed by a per-node `hostPath`
    volume, so a pod restart resumes from its last read offset instead
    of re-reading every file from the beginning - verified by deleting an
    agent pod and confirming its replacement logged a normal volume, not
    another flood of `429`/`503`/`Exporting failed` entries. **Gotcha**:
    the collector image runs as non-root, but Kubernetes creates
    `hostPath` directories root-owned and does **not** apply `fsGroup` to
    them (unlike most other volume types) - needed a tiny root
    `initContainer` (`chmod 0777` on the checkpoint directory before the
    main container starts) to make it writable.

  This also exposed a separate Loki distributor/ingester ring desync
  after a rolling restart (`"at least 1 live replicas required across
  different availability zones"`, referencing stale pod IPs) that
  needed a manual `kubectl rollout restart deployment/loki-distributor`
  to clear once - **root cause found and fixed** in a later pass:
  `helm/values/loki-values.yaml` sets `commonConfig.replication_factor:
  1` (deliberately minimal for a demo), but the `grafana/loki`
  distributed chart's `ingester.zoneAwareReplication.enabled` defaults
  to `true` regardless - creating 3 separate `zone-a`/`zone-b`/`zone-c`
  ingester StatefulSets (1 replica each) designed around
  `replication_factor: 3` (one copy per zone), confirmed live via
  `kubectl get pods` showing exactly those three. With `replication_factor:
  1`, that mismatch meant a rolling restart of any single zone's
  ingester could transiently fail zone-aware's multi-zone health check
  even though, with RF 1, only one replica was ever needed at all.
  Fixed by explicitly setting `ingester.zoneAwareReplication.enabled:
  false` to match the file's own already-stated minimal-RF intent -
  also drops 2 of the 3 ingester pods this was silently running the
  whole time. **Confirmed live**: rolling-restarting the resulting
  single-ingester StatefulSet (`kubectl rollout restart
  statefulset/loki-ingester`) completed on its own within the normal
  timeout, no manual intervention needed (previously required a manual
  distributor restart to clear). One transitional gotcha hit while
  *applying* this fix, not a recurrence of the bug: switching the
  running cluster from 3 zone-ingesters to 1 plain one left the 3 old
  zone instances' stale entries in the ring, and the new single
  ingester refused to go `Ready` until they aged out - the ring's `/ring`
  HTTP page (on the distributor) has a manual "Forget" button per stale
  instance (`POST /ring` with `forget=<instance-id>`) that resolves
  this immediately instead of waiting out the heartbeat timeout, useful
  to know for any future one-time ring-topology change. A separate bug
  (see next entry) was why most namespaces besides `observability`
  weren't landing in Loki at all, independent of this backlog/rate-limit
  problem.
- **`filelog`'s `container` operator was pointed at the wrong path,
  silently mislabeling almost every log line as coming from the agent
  itself**: `include: [/var/log/containers/*.log]` matched the
  Kubernetes-provided symlinks
  (`<pod>_<namespace>_<container>-<containerID>.log`), but the
  `container` operator's path-based metadata extraction (`format:
  containerd`) is written to parse the *real* kubelet files it points
  to - `/var/log/pods/<namespace>_<pod>_<uid>/<container>/<N>.log` (see
  the [OTel container log parser
  docs](https://opentelemetry.io/blog/2024/otel-collector-container-log-parser/)).
  Every line failed with "failed to detect a valid log path", but the
  operator still forwards entries after a failed parse - they just
  arrived at the gateway with no `k8s.*` attributes set, so the gateway's
  `k8sattributes` processor fell back to its connection-based
  association and tagged literally everything with the agent pod's own
  identity (`namespace=observability`), regardless of which pod actually
  produced the log. This is why Loki only ever showed `observability` as
  a namespace, even after the RBAC/containerd-format/checkpoint fixes
  above. Fixed by pointing `include` at `/var/log/pods/*/*/*.log`
  directly (matching the exclude patterns for the collector's own logs to
  the new path shape too) - verified live: pods across multiple
  namespaces (`kube-system`, plus many `observability` pods beyond just
  the collectors themselves) now show up in Loki under their real
  `k8s_pod_name`/`k8s_namespace_name`, and no rate-limit flood occurred
  even though this necessarily triggered a one-time fresh backlog read
  (new file paths have no prior checkpoint).
- **Dashboard 15983 ("OpenTelemetry Collector") shows "No data" on
  several panels the first time it's opened**: several separate causes,
  only some fixable on our side:
  - **"Uptime by Service Instance"**: the underlying data is present and
    correct (verified directly against Mimir) - this is a first-load
    quirk of the dashboard's chained `query_result()`-based template
    variables (`$job` → `$divider` → `$suffix_total`/`$suffix_seconds`),
    which don't always resolve in dependency order on the very first
    render. Reload the dashboard page or re-pick `otelcol-contrib` in the
    **job** dropdown at the top to
    fix it.
  - **"Service Instance Details" - genuine bugs in the vendored dashboard
    query, not a reload issue**: its `or`-combined query had two broken
    branches. The first branch filtered on `service_version=".+"` using
    plain label *equality* (`=`) instead of a regex match (`=~`) - since
    no series literally has the two-character value `".+"`, that branch
    always returned zero results, in any environment, regardless of our
    setup. The second (fallback) branch self-joined the entire
    `target_info` metric via `group_left` with no `job` filter on the
    inner join - harmless in a single-purpose Prometheus setup, but in
    ours `target_info` also carries one row per Kubernetes pod (from
    `resource_to_telemetry_conversion` on the hostmetrics/kubeletstats
    pipeline), several of which share a `(job, instance)` pair, so
    Prometheus's vector matching throws a hard "found duplicate series"
    execution error - and since PromQL's `or` doesn't isolate errors
    between its two sides, that failure broke the whole panel even though
    the first branch would otherwise have worked. Fixed in our vendored
    copy: corrected `=` to `=~`, and dropped the fragile fallback branch
    entirely (the corrected first branch alone now covers it).
  - **"RPC server/client" / "HTTP server/client" panels**: the collector
    only emits its own gRPC/HTTP receiver-handling metrics at
    `service.telemetry.metrics.level: detailed` (now set on the gateway
    in `otel-gateway-collector.yaml`). The resulting metric names don't
    match what the dashboard's `${prefix}rpc_server_duration_bucket`
    pattern expects, though - the underlying OTel RPC semantic convention
    was renamed (`rpc.server.duration` → `rpc.server.call.duration`,
    with no `otelcol_` prefix on top) since this dashboard revision was
    built. Patched "RPC server duration" and "RPC server responses by
    status code" in our vendored copy to the real metric name
    (`rpc_server_call_duration_bucket`/`_count`) and label
    (`rpc_response_status_code` instead of `rpc_grpc_status_code`) - both
    verified with real data. Two panels remain genuinely empty, not
    fixable by a rename: "RPC server request size" has no equivalent
    metric at all in this collector version (only call *duration* is
    tracked, not request size), and "HTTP server duration" is empty
    because nothing currently sends OTLP/HTTP to the gateway (only
    OTLP/gRPC is used - agents and the demo apps all export via gRPC).
    Interestingly, `http_client_request_duration_*` *does* exist (the
    collector's own outbound HTTP calls, e.g. to Loki's OTLP endpoint) -
    just not the inbound "server" side this panel asks for.
  - **"Spans Flow" node graph throws a JS error ("id field is required
    for nodes data frame")** instead of showing "No data"**: a Grafana
    Node Graph panel quirk when the query returns zero nodes - expected
    as long as no traces are flowing (no trace-producing app installed
    yet), resolves itself once one is.
  - The **"Namespaces"** panel queried
    `otelcol_otelsvc_k8s_namespace_added/updated`, which no longer exists
    in collector-contrib 0.158.0 (only pod-level watch metrics remain) -
    patched in our vendored copy to
    `otelcol_otelsvc_k8s_pod_added_total`/`_updated_total` instead. Since
    collector-contrib 0.160.0 k8sattributes emits only the new-format
    `otelcol_k8s_watcher_pod_*` metrics; the panels use those now.
- **Budget enforcement briefly dropped the AKS platform's own telemetry,
  on purpose - now fixed by resizing**: `9001-prod`'s (renamed to
  `4087-prod` since, same tenant) per-tenant limits
  (see [Multi-Tenancy (Onboarding)](#b9-multi-tenancy-onboarding)) were
  first computed from a demo-sized "M" manifest entry, which turned out
  too small for the AKS Cluster platform's real metrics volume (3 nodes'
  worth of hostmetrics/kubeletstats, plus the whole LGTM stack monitoring
  itself) - confirmed via `cortex_discarded_samples_total{reason=
  "rate_limited", user="9001-prod"}` actively incrementing. That was a
  deliberate choice (prove enforcement actually works end-to-end, rather
  than pick a generous placeholder nobody could verify against), not a
  bug. Resolved by bumping `9001-aks-cluster.yaml` to size `L` (in the
  separate onboarding repo, at the time) and regenerating the override in
  `helm/values/mimir-values.yaml`/`loki-values.yaml` to match (`python3
  scripts/calculate-ingestion-budget.py --app 9001 --env prod --size L`)
  - confirmed the discard counter stopped climbing after applying it.

- **Per-system dashboards silently overwrote each other in Grafana across
  a system's environments**: `kubernetes/dashboards/templates/system-dashboard.template.json`
  originally keyed `uid`/`title` by `system_id` alone. A system with more
  than one environment (e.g. `1286-linux-basis`: eng/at/prod) generates
  one dashboard file per environment, but since all three shared the
  same `uid` (`system-1286`), each apply overwrote the previous one in
  Grafana - only whichever environment synced last was ever visible.
  Only surfaced once a multi-environment system was actually onboarded
  end-to-end (`9001-prod`/now `4087-prod`, the only one live before, has
  just one environment). Fixed by keying `uid` on the full tenant ID
  (`system_id-env`, already unique) instead. Cleaning up the *already*
  wrongly-overwritten dashboards that existed under the old, collided
  `uid`s needed an extra step: Grafana's file-based dashboard
  provisioner (`disableDeletion: false`, 30s reload interval) is
  supposed to remove a dashboard once its source file disappears, but
  didn't reliably do so here (its own `POST
  /api/admin/provisioning/dashboards/reload` and the sidecar's normal
  reload cycle both ran, yet a stale entry stuck around, `provisioned
  dashboard cannot be deleted` on manual `DELETE
  /api/dashboards/uid/...`) - deleting the ConfigMap outright (not just
  applying a changed one) and letting the *removal* propagate is what
  actually worked, though even that left one dashboard (`system-9001`)
  permanently stuck - harmless (its `uid` collides with nothing live)
  and left in place rather than chased further.

- **Every generated dashboard displayed the wrong tenant's data**,
  despite each having its own correct `uid`/tenant ID: they all
  referenced the same generic `Mimir`/`Loki` Grafana datasources
  (pinned to one tenant, `4087-prod`), because `generate-system-dashboard.py`
  defaulted to those names and nothing gave each tenant its own
  datasource. Only surfaced once several tenants actually had live
  dashboards side by side (each one's panels quietly showed identical
  numbers). Fixed by giving every tenant its own
  `Mimir-<tenant_id>`/`Loki-<tenant_id>`/`Tempo-<tenant_id>` triplet
  (`scripts/provision.py`'s `update_grafana_datasources()`) and changing
  the generator's default to match. A related, separate bug surfaced
  fixing this, back when onboarding still lived in its own separate
  repo: its `tenants:apply` CI job's `git add` command never listed
  `helm/values/grafana-values.yaml` - the job correctly computed the
  new datasources in its own checkout but silently never staged/
  committed them, so only the (much smaller) dashboard file changes
  ever reached this repo. Applying the fix to a live cluster also needs
  a step easy to forget: updating `grafana-values.yaml` only changes
  what Grafana's *datasources* look like (`helm upgrade grafana`) -
  the *dashboard* ConfigMaps holding the panel JSON have to be
  re-applied separately (the `install.sh` dashboard loop) before a
  dashboard's panels actually reference the new datasource names in
  the running cluster, since the two aren't coupled at deploy time.

- **Every job in the pipeline has now run green at least once against
  real resources** - `validate:yaml`, `validate:shell`,
  `build:terraform-plan`, `deploy:infra`, `deploy:observability-stack`,
  and `destroy:infra` have all run green (including a full
  from-scratch cluster rebuild, not just a re-apply). **All eight
  `deploy-fleets:*` jobs and all eight `deploy-instrumentations:*` jobs have run green**
  too (platform-basis fleet+instrumentation: 1229/1286/1294/4015;
  applications fleet+instrumentation: 4711/4720/4721/4722, 4721's own
  job also covering its dedicated PostgreSQL database), including
  a full re-run of both stages after the client-template restructuring
  (platform vs. middleware) to confirm the new templates work end to
  end, not just in isolated manual testing.
  **All six fleet-teardown `destroy:*` jobs plus `destroy:observability-stack`
  have also now run green**, the last fully-unverified path (see
  below for the ordering these two gained as a result, and the NSG bug
  their first real run surfaced). Two real bugs were found and fixed
  along the way in the deploy path:
  - `deploy-fleets:4711-mitarbeiterverzeichnis` initially failed with "Host key
    verification failed", and fixing just that surfaced a deeper
    problem - there's no way to share an SSH *private* key between the
    job that creates `vm-rocky-demo` (`az vm create --generate-ssh-keys`
    generates one fresh per run, thrown away with the container) and
    any later job that needs to reach it (every CI job runs in a fresh,
    non-persistent container). Fixed by moving all `vm-rocky-demo`
    interaction onto `az vm run-command` instead of SSH, the same
    approach `vm-windows-demo` already used - see
    `scripts/fleet-1286-linux-basis.sh`'s own comment. Verified live
    after the fix. Also fixed in the same pass:
    `deploy-fleets:1286-linux-basis`/`deploy-fleets:1229-windows-basis` weren't
    idempotent against an already-provisioned VM (`az vm create`
    rejected the redeploy once a differing SSH key/admin password was
    generated on a second run) - both now check whether the VM already
    exists first.
  - `deploy-instrumentations:4720-otel-astronomy-shop` failed with `Error: repo
    open-telemetry not found` - same fresh-container root cause: the
    `helm repo add open-telemetry` done in `fleet-4720-otel-astronomy-shop.sh`
    (a different job) doesn't carry over. Fixed by adding the same
    `helm repo add`/`helm repo update` there too (commit `740bf28`) -
    the identical bug was also found and fixed in `deploy-tenants.sh`
    (missing `helm repo add grafana`) while looking for it, though that
    one's never been run as a real CI job so wasn't caught live.
    Re-run of `deploy-instrumentations:4720-otel-astronomy-shop` confirmed the
    fix.

  The first real run of the six fleet-teardown `destroy:*` jobs
  (previously untested) found one more real bug: `destroy-fleet-1286-linux-basis.sh`/
  `destroy-fleet-1229-windows-basis.sh` deleted each VM's NIC, public IP,
  and OS disks, but not its NSG (`vm-rocky-demoNSG`/`vm-windows-demoNSG`,
  both created implicitly by the original `az vm create`, no explicit
  name given) - left behind after every run until fixed, cleaned up by
  hand once found live. Fixed by adding `az network nsg delete` to both
  scripts. This also motivated a real ordering requirement in the
  `destroy` stage: `destroy:observability-stack` now `needs` all six
  fleet-teardown `destroy:*` jobs, and `destroy:infra` `needs`
  `destroy:observability-stack` in turn (previously all three were
  fully independent) - see [Destroy](#destroy) for why forcing that
  order matters even though the AKS cluster going away would eventually
  take everything inside it down anyway.
- **`tenants:rollout` has now run as a real CI job and succeeded** -
  Mimir/Loki tenant budgets upgraded, all 14 datasource ConfigMaps and
  14 dashboard ConfigMaps applied, no errors (confirming the `helm repo
  add grafana` fix above actually works live, not just in theory). Its
  underlying mechanics were already verified live before that too (a
  datasource ConfigMap shows up in Grafana within seconds, no restart;
  querying through it returns real per-tenant data).
- **The AKS cluster identity's `Network Contributor` role on `aks-vnet`
  is now Terraform-managed** (`azurerm_role_assignment` in
  `terraform/modules/aks-cluster/main.tf`) - originally a manual step
  that had to be redone after every full
  `terraform destroy` (a fresh `apply` gives the cluster a brand-new
  identity object id, so the old role assignment didn't carry over),
  found the hard way when `otel-gateway-internal`'s LoadBalancer stayed
  `<pending>` forever with `AuthorizationFailed` on `subnets/read`.
  Worth knowing if it ever recurs (e.g. a `terraform apply` outside the
  usual `build:terraform-plan`/`deploy:infra` flow): in this Playground
  sandbox subscription, RBAC propagation after granting the role was
  observed taking over 30 minutes in one case - deleting and
  re-creating the same role assignment (`az role assignment delete`
  then `create` again, or `terraform apply
  -replace=module.aks.azurerm_role_assignment.aks_identity_network_contributor`)
  appeared to force faster propagation when just waiting didn't.
- **CI SP needs `User Access Administrator` on `aks-vnet`, and that
  grant does NOT survive `aks-vnet` being deleted and recreated, despite
  its resource ID being deterministic by name**: `Contributor` (from
  [A3](#a3-create-the-gitlab-ci-service-principal)) can manage resources
  but can't *grant* roles - without this extra grant,
  `azurerm_role_assignment.aks_identity_network_contributor` (the fix
  above) itself fails with `AuthorizationFailed` on
  `Microsoft.Authorization/roleAssignments/write`. Originally assumed
  (wrongly) to be a genuinely one-time grant, reasoning that a
  deterministic resource ID meant the role assignment would keep
  applying across future destroy+rebuild cycles too - **found false
  live, repeatedly**, across several full `destroy:infra` +
  `deploy:infra` cycles: `aks-vnet` was itself Terraform-managed at the
  time (created fresh in the same apply as the AKS cluster), and Azure
  does not carry a scope's role assignments across that scope's own
  delete+recreate, deterministic ID or not - so the grant silently had
  to be redone by hand after every single cycle, exactly the kind of
  recurring manual step this project tries to avoid. Fixed by making
  `aks-vnet` itself a one-time manual bootstrap resource, decoupled from
  the destroy/rebuild cycle the same way the DNS zone already was (see
  [A5](#a5-create-aks-vnet--grant-ci-sp-role-assignment)) - now this
  grant is genuinely one-time, since its scope no longer gets deleted.
- **`kubernetes_manifest` (hashicorp/kubernetes provider): "Provider
  produced inconsistent result after apply... .object: wrong final
  value type: incorrect object attributes"** - hit reproducibly (twice,
  both against an empty Terraform state) applying
  `otel-gateway-collector.yaml` (originally in
  `terraform/environments/observability-stack-crs`, since moved to
  `terraform/environments/tenants` - the workaround below moved with
  it, unchanged), while the otherwise identical `otel-agent-daemonset.yaml`
  (same `OpenTelemetryCollector`
  CRD, simpler `spec.config`) applies cleanly every time. A known
  upstream provider limitation with complex/loosely-typed CRD schemas,
  not a config mistake - confirmed via `kubectl` both times that the
  object is actually created correctly and healthy in the cluster
  despite the error (the bug is in Terraform's own post-apply state
  reconciliation, not the real Kubernetes API call). Considered the
  `gavinbunney/kubectl` provider (schema-less, sidesteps the bug
  entirely) but chose to stay on official providers only, consistent
  with the reasoning in
  `terraform/environments/observability-stack-crs/versions.tf`. Fixed
  by moving just this one resource to a `null_resource` +
  `kubectl apply`/`kubectl delete` (`when = destroy`) local-exec pair,
  triggered on a hash of the YAML file so onboarding-driven changes
  (the tenant allowlist regex, see that file's own comment) still
  propagate automatically - trades away native Terraform drift
  detection for this one resource only, see that resource's own comment
  for the full reasoning.
- **`azurerm_linux_virtual_machine`'s `source_image_id` rejects the
  Community Gallery image ID casing Azure itself uses everywhere else**
  (`az vm create --image`, the Azure Portal): `/CommunityGalleries/<gallery>/Images/<image>/Versions/<version>`
  fails with a segment-parsing error ("the number of segments didn't
  match" against six different ID formats it tried) - the provider's ID
  parser is case-sensitive and only accepts
  `/communityGalleries/<gallery>/images/<image>/versions/<version>`
  (lowercase leading letter on each segment name). Found live on
  `terraform/modules/client-vm`'s first real apply for `vm-rocky-demo`;
  fixed by lowercasing the default `linux_image_id` value.
- **Six real bugs found live testing the Ansible milestone's
  `deploy-instrumentations:1286-linux-basis`/`deploy-instrumentations:1229-windows-basis`
  CI jobs, in order** (both jobs now run green end to end):
  1. `pip: command not found` - the `azure-cli:2.65.0` image (Azure
     Linux/`tdnf`-based) has `python3` but no `pip` binary on `PATH`.
     Fixed: `python3 -m pip` instead of bare `pip`, installing
     `python3-pip` via `tdnf` first if the module itself isn't present
     either.
  2. `[WARNING]: Ansible is being run in a world writable directory...
     ignoring it as an ansible.cfg source` - GitLab CI's docker executor
     checks the repo out into exactly such a directory, so
     `ansible/ansible.cfg`'s `inventory`/`roles_path` settings were
     silently dropped, leaving no inventory parsed and the
     `platform-linux` role not found in the default playbook-relative
     `roles/` path. Fixed: pass `-i inventory/generated.ini` and
     `$ANSIBLE_ROLES_PATH` explicitly in the CI job instead of relying on
     `ansible.cfg` auto-discovery (which still works fine for a
     local/manual run from a normal directory).
  3. `couldn't resolve module/action 'ansible.windows.win_get_url'` in
     the **Linux** job, despite `--limit platform_linux` - Ansible
     resolves module references for every play in a playbook file up
     front regardless of `--limit`, so the single combined
     `onboard-platform.yml` made the Linux job's `ansible-playbook` fail
     parsing the *other* play's `platform-windows` role, since that
     job never installs the `ansible.windows` collection. Fixed: split
     into `onboard-platform-linux.yml`/`onboard-platform-windows.yml`,
     one play each - each job's Ansible dependencies now stay genuinely
     independent.
  4. `'otel_collector_version' is undefined` on
     `deploy-instrumentations:1229-windows-basis`'s first real task - Ansible
     only auto-loads `group_vars/` relative to the playbook or inventory
     directory, not an arbitrary project root; `ansible/group_vars/`
     matched neither `ansible/playbooks/` nor `ansible/inventory/`.
     Fixed: moved to `ansible/playbooks/group_vars/` (playbook-relative,
     since the inventory directory holds a dynamically generated,
     gitignored file per run - not a stable place to anchor committed
     vars).
  5. `SQLite error on "/var/lib/dnf/history.sqlite"... attempt to write
     a readonly database` installing the collector RPM on
     `deploy-instrumentations:1286-linux-basis` (SSH connection itself already
     working fine at this point) - `rocky` (the connecting SSH user)
     has no root privileges by default, unlike the old
     `az vm run-command` approach (always runs as root). Fixed: `become:
     true` on the Linux play - confirmed live, passwordless sudo for
     the initial admin user just worked, no `become_password` needed.
  6. `Destination directory /etc/systemd/system/otelcol-contrib.service.d
     does not exist` - `ansible.builtin.copy` (unlike the original
     script's `mkdir -p` + `tee`) doesn't create missing parent
     directories on its own. Fixed: an explicit
     `ansible.builtin.file: state=directory` task before the `copy`.

  Both jobs have now run green end to end: `deploy-instrumentations:1229-windows-basis`
  (all 6 tasks, WinRM connection including the self-signed cert
  confirmed working live) and `deploy-instrumentations:1286-linux-basis` (all 9
  tasks, SSH connection + `become: true` privilege escalation confirmed
  working live) - the platform-basis tier of the Ansible migration is
  complete.
- **`ansible.windows.win_firewall_rule` doesn't exist** - found live on
  `deploy-fleets:4722-spesenabrechnung`'s first real run: `[ERROR]: couldn't resolve module/action
  'ansible.windows.win_firewall_rule'`. That module lives in
  `community.windows`, a collection CI never installs (only
  `ansible.windows`, via `.install_ansible_windows`). Fixed: a literal
  `New-NetFirewallRule` `win_shell` call instead, matching the original
  script and the same literal-translation approach already used for
  `sc.exe create`/`sc.exe failure` in the same role.
- **`ansible.builtin.command` doesn't glob** - found live on
  `deploy-fleets:4711-mitarbeiterverzeichnis`'s first real run: `chmod +x
  /opt/tomcat/bin/*.sh` failed with `"chmod: cannot access
  '/opt/tomcat/bin/*.sh': No such file or directory"` - `command` runs
  the binary directly, no shell in between to expand the glob, unlike
  the original script's plain `bash` line. Fixed: `ansible.builtin.shell`
  instead.

  With both fixes in, all four jobs (`deploy-fleets:4711-mitarbeiterverzeichnis`,
  `deploy-fleets:4722-spesenabrechnung`, `deploy-instrumentations:4711-mitarbeiterverzeichnis`,
  `deploy-instrumentations:4722-spesenabrechnung`) have run green end to end -
  the VM-based middleware/app tier of the Ansible migration is complete.
- **`validate:ansible`'s `ansible-galaxy collection install
  ansible.windows` call kept hitting `galaxy.ansible.com` itself, not a
  bug in this repo** - first `[ERROR]: Missing expected 'results' in
  ansible-galaxy cache` (a cache-corruption bug, `--no-cache` "fixed"
  it), then `[ERROR]: ... (HTTP Code: 502, Message: Bad Gateway)` even
  with `--no-cache` and a `retry: 2` - a real, non-transient Galaxy
  outage, not a quick blip retries could ride out. Fixed for good by
  sidestepping Galaxy entirely: `pip install ansible` (the full
  community package) instead of `ansible-core`, since it already bundles
  `ansible.windows` - no separate collection-install network call
  needed at all for a job that only needs the module names to resolve,
  not the latest collection version.
- **`azurerm_dns_a_record` refuses to create over a pre-existing record
  not in Terraform's state** - found live on this environment's
  (`terraform/environments/fleet-4139-postgresql`, then still onboarded
  as two separate systems - see Multi-Tenancy's "Middleware/runtime
  tenants" note for why 4139 was later folded into 4721) first real
  run: `Error: A resource with the ID ".../A/kundenverwaltung" already
  exists - to be managed via Terraform this resource needs to be
  imported into the State`. The old shell scripts' own delete-then-add
  `az network dns record-set` dance had left both `kundenverwaltung`
  and `astronomy-shop` A records behind from an earlier session,
  pointing at a stale Traefik IP from a previous cluster incarnation.
  Not fixable from the Terraform side alone for a first transition -
  fixed by deleting both stale records by hand (`az network dns
  record-set a delete`) so the next `terraform apply` creates and
  tracks them fresh. One-time cleanup, not expected to recur once
  Terraform owns the record going forward.
- **`deploy-fleets:4139-postgresql`/`deploy-fleets:4721-kundenverwaltung` used to
  share one Terraform state/`var.instrument`, so whichever of the four related
  jobs (either deploy-fleets:* job, either deploy-instrumentations:* job) ran *last*
  won for both systems** - found live: running
  `deploy-instrumentations:4139-postgresql` (`instrument=true`, created
  `postgres-otel-collector`) and then `deploy-fleets:4721-kundenverwaltung`
  (`instrument=false`, same state) afterward silently reverted the
  instrumentation - `INSTRUMENT` back to `false`, `postgres-otel-collector`
  destroyed again. Not a bug, an inherent consequence of the combined-environment
  design decision (see that environment's own header comment) - fixed at
  the time with sequencing discipline (run **both** deploy-fleets jobs to
  completion before running **either** instrumentation job). This hazard
  is now moot: once 4139 folded into 4721 as a system (see
  Multi-Tenancy's "Middleware/runtime tenants" note), the redundant
  `deploy-fleets:4139-postgresql`/`deploy-instrumentations:4139-postgresql`
  jobs were removed - only `deploy-fleets:4721-kundenverwaltung` and
  `deploy-instrumentations:4721-kundenverwaltung` apply this state now,
  one entry point per stage, sequenced by the existing `needs:` chain
  like any other fleet.
- **An unquoted `:` in a plain YAML scalar silently becomes a mapping,
  not a parse error** - found via GitLab's own CI lint (`jobs:
  deploy-instrumentations:1229-windows-basis:script config should be a string
  or a nested array of strings`) when replacing
  `scripts/lib-wait-gateway-ip.sh` with a `terraform output` read:
  `- echo "Gateway internal IP: $GATEWAY_IP"` parsed as a one-key
  mapping (`{'echo "Gateway internal IP': '$GATEWAY_IP"'}`), not a
  string - the double quotes only wrap part of the line, so YAML still
  treats the whole thing as a *plain* scalar, and plain scalars can't
  contain a bare `: `. A generic `yaml.safe_load` doesn't catch this
  (it parses to a valid mapping, just not the one intended) - only
  GitLab's schema-level validation, which checks that every `script`
  leaf is actually a string, caught it. Fixed by wrapping the whole
  line in single quotes. Both new Terraform outputs this milestone
  introduced (`gateway_internal_ip` here, the four K8s-native
  environments' own outputs) are confirmed working live now across all
  four consumer jobs (1286/1229/4711/4722).
- **An unpinned `ansible-galaxy collection install ansible.windows`
  silently broke WinRM entirely** - found live on
  `deploy-fleets:4722-spesenabrechnung`: `[ERROR]: Unable to execute ssh
  command line on a controller: [Errno 2] No such file or directory:
  b'ssh'` on the very first Windows task, Ansible falling back to the
  `ssh` connection plugin instead of `winrm`. Every prior successful
  run this project had used `ansible.windows:3.7.0`; this run silently
  picked up a freshly-released `3.8.0` instead (`--force` with no
  version pin always installs latest) - a real upstream regression, not
  a config mistake on our side. Fixed by pinning the version
  (`ansible-galaxy collection install ansible.windows:3.7.0 --force`).
- **`null_resource.otel_gateway_collector`'s destroy-time provisioner
  needed a kubeconfig *file* that never existed in a fresh CI
  container** (found while this resource still lived in
  `observability-stack-crs`, before it moved to
  `terraform/environments/tenants` - the fix below moved with it,
  unchanged) - found live on
  `destroy:observability-stack`: `Error running command 'kubectl delete
  opentelemetrycollector...': ... The connection to the server
  localhost:8080 was refused`. The provisioner pointed `KUBECONFIG` at
  `local_sensitive_file.kubeconfig`'s file *path*, but every CI job
  runs in its own fresh container/checkout - that file was never
  written to disk in *this* container (Terraform doesn't re-materialize
  a resource that's about to be destroyed anyway), so kubectl silently
  fell back to no-config-found behavior. Fixed two ways: the trigger
  now stores the kubeconfig *content* itself (so the destroy-time
  provisioner writes its own temp file from a value already in state,
  self-contained regardless of what's on disk), and the provisioner got
  `on_failure = continue` - this cleanup is best-effort only anyway,
  since the AKS cluster this object lives in gets destroyed right after
  via `destroy:infra`, so a failure here should never block the whole
  destroy chain.
- **`correlation.transaction_id` (UC3 baggage propagation) confirmed
  live to never surface as a Tempo span attribute on the Astronomy
  Shop's own services** - previously left as an honestly-flagged
  "unverified" gap (see [B10](#b10-telemetry-schema)), closed out once
  the full fleet was onboarded and real UC3 traffic existed to check
  against. Ran `scripts/trigger-uc3-transaction.py`'s own request by
  hand (the script itself hit a local Python SSL cert-store issue in
  this sandbox unrelated to the target - `curl` against the same URL
  worked fine, confirming the site's own TLS was never the problem),
  then queried Tempo's `/api/v2/search/tags` for tenant `4720-prod`:
  none of the 206 known span attribute names contain "correlation".
  Root-caused against the actual upstream project, not assumed: the
  `open-telemetry/opentelemetry-demo` chart has no baggage-to-span-
  attribute processor wired into any of its services - tracked
  upstream as `open-telemetry/opentelemetry-demo#1572` (open,
  unimplemented, no config flag). Several individual OTel SDKs (Go/
  Python/JS/.NET/Ruby) do support such a processor, but enabling it
  would mean editing that chart's own per-service source across
  several languages - the same source-access boundary this repo
  already draws elsewhere for 4720 (e.g. its Pyroscope profiling
  scope), so left as a confirmed, cited upstream limitation rather
  than worked around. `correlation.request_id` (the achievable half,
  Kundenverwaltung/Spesenabrechnung's own code) was verified live in
  the same pass - a real request on each app makes the attribute
  appear in Tempo immediately (Spesenabrechnung specifically needs a
  real `POST /expenses`, not `GET` - the attribute is only set inside
  that handler).
