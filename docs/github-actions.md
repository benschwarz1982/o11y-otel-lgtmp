# CI/CD with GitHub Actions

The repository runs on **GitHub Actions** (primary) and still carries the
original **GitLab CI** pipeline (`.gitlab-ci.yml`). Both drive the same
Terraform code, Ansible roles and scripts; the CI-specific logic lives in
`ci/scripts/`, so the workflow files stay thin.

## Workflows

| Workflow | Trigger | Runner | Does |
|---|---|---|---|
| [CI](../.github/workflows/ci.yml) | pull request, push to `main` | GitHub-hosted | actionlint + zizmor, yamllint, shellcheck, ruff, ansible-lint, manifest schema + generated-file check, alert/SLO rule tests, pip-audit, `terraform fmt`/`validate`, hadolint, kubeconform, gitleaks, trivy config |
| [CI images](../.github/workflows/ci-images.yml) | change under `ci/images/`, manual | GitHub-hosted | builds the 4 CI tool images, pushes them to GHCR with SBOM + build provenance attestation, scans them |
| [Infra plan](../.github/workflows/infra-plan.yml) | push to `main` touching AKS/network Terraform | GitHub-hosted | `terraform plan` of the infra environment |
| [Deploy](../.github/workflows/deploy.yml) | manual | self-hosted | `everything` = rebuild from zero: infra → observability stack → tenants → fleets → instrumentations → aiops; every step can also run alone, optionally `plan_only` |
| [Destroy](../.github/workflows/destroy.yml) | manual, type `destroy` | self-hosted | reverse order: aiops → fleets + tenants → observability stack → infra |
| [Tenants](../.github/workflows/tenants.yml) | merge to `main` touching tenant config, manual | hosted + self-hosted | verifies the generated files, rolls out tenant overrides, datasources, dashboards, gateway CR, rules |
| [Self-service request](../.github/workflows/onboarding.yml) | issue from the self-service form, manual | GitHub-hosted | turns an onboarding/update/offboarding request into a pull request |
| [Demo](../.github/workflows/demo.yml) | manual | self-hosted | break/fix of the four demo use cases |
| [Pages](../.github/workflows/pages.yml) | change under `form/` | GitHub-hosted | publishes the self-service form |
| [Security scans](../.github/workflows/security-scans.yml) | weekly, manual | GitHub-hosted | pip-audit + trivy on the CI images (new CVEs without a repo change) |

### GitLab job → GitHub workflow

| GitLab CI | GitHub Actions |
|---|---|
| `validate:*` | CI |
| `build:ci-image-*`, `build:ci-image-scan` | CI images (+ Security scans) |
| `build:terraform-plan` | Infra plan (or Deploy, scope `infra`, `plan_only`) |
| `deploy:infra`, `deploy:observability-stack`, `deploy-aiops:aiops` | Deploy, scope `infra` / `observability-stack` / `aiops` |
| `deploy-fleets:*` | Deploy, scope `fleets` (+ `systems`) |
| `deploy-instrumentations:*` | Deploy, scope `instrumentations` (+ `systems`) |
| `tenants:apply` + `tenants:rollout` | Tenants |
| `tenants:create-mr` / `update-mr` / `offboarding-mr` | Self-service request |
| `pages` | Pages |
| `demo:*` | Demo |
| `destroy:*` | Destroy |

## Design

- **No stored cloud credentials.** Azure sign-in is GitHub OIDC
  (`azure/login`, Terraform `ARM_USE_OIDC`) against a user-assigned
  managed identity whose federated credential only trusts the GitHub
  environment `demo`. Terraform state lives in an Azure Storage Account
  with shared-key access disabled (Entra ID auth only), versioning and
  soft delete.
- **Least privilege.** Every workflow starts with `permissions: {}`;
  jobs get only what they need (`id-token: write` only where Azure is
  used). The identity is Contributor on the resource group only; it may
  grant exactly one role (Network Contributor) on exactly one scope
  (`aks-vnet`), enforced by an ABAC condition.
- **Supply chain.** All actions are pinned to a full commit SHA; CI
  images carry SBOM and SLSA build provenance attestations
  (`gh attestation verify oci://ghcr.io/<owner>/<repo>/ci-tools/terraform:v1 --repo <owner>/<repo>`).
  zizmor audits the workflows themselves.
- **Public repository, self-hosted runner.** Pull requests (including
  from forks) only ever run on GitHub-hosted runners without secrets.
  The self-hosted runner is used only by workflows a maintainer starts
  (`workflow_dispatch`, push to `main`) and by jobs bound to the `demo`
  environment, which only accepts `main`. Jobs run as containers from
  the CI images and remove the sensitive files they created
  (keys, inventory, kubeconfigs) at the end.
- **Serialized changes.** Deploy and Destroy share one concurrency group
  (never two at once against the environment); tenant rollouts have
  their own group plus the newest-wins guard in
  `ci/scripts/tenants-rollout.sh`.

### Accepted risks (demo trade-offs)

- **Self-hosted runner on a public repository.** A personal account has
  no runner groups, so the runner cannot be restricted to the deploy
  workflows on `main`. A pull request that changes a workflow could
  target it once a maintainer approves the run - with Docker access on
  the management VM and the IP the fleet VMs trust. Mitigation:
  "Require approval for all external contributors", and **never approve
  a fork run that changes anything under `.github/`**. Production: an
  organization with a runner group limited to selected workflows, or a
  separate private deploy repository.
- **Deploy identity inside its own scope.** The playground subscription
  allows only the one resource group, so `id-otel-demo-deploy` lives in
  the group it is Contributor on and could add federated credentials to
  itself. Production: the identity in a separately administered
  resource group.

Why a self-hosted runner at all: the fleet VMs accept SSH/WinRM only from
the management VM's public IP (`mgmt-gitlab-runner-pip`, see
`terraform/environments/fleet-*`). GitHub-hosted runners have changing
IPs - opening the NSGs to them would undo that restriction.

## Setup

One-time, in this order.

1. **Repository.** Create the GitHub repository (public) and push `main`.
   Settings → General: enable "Automatically delete head branches".
   Settings → Actions → General: "Require approval for all external
   contributors"; workflow permissions "Read repository contents" and
   "Allow GitHub Actions to create and approve pull requests" (the
   self-service workflow opens pull requests).
2. **Azure (Cloud Shell, as Owner of the resource group).** The README
   section A prerequisites stay the same (resource group, DNS zone,
   `aks-vnet`, cert-manager service principal); A3-A5 (GitLab CI service
   principal) are replaced by:

   ```bash
   RG=<resource-group> GITHUB_REPO=<owner>/<repo> ./bootstrap/bootstrap.sh
   ```

   It prints the repository variables for the next step.
3. **Variables and secrets.** Settings → Secrets and variables → Actions.

   Repository **variables**:

   | Variable | Value |
   |---|---|
   | `AZURE_RESOURCE_GROUP` | the resource group (same as `RG` above) |
   | `DNS_ZONE` | Azure DNS zone of the public hostnames, e.g. `sre.example.com` |
   | | `AZURE_RESOURCE_GROUP`, `DNS_ZONE`, `ACME_EMAIL` may also be `demo` environment secrets (masked in logs) |
   | `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID` | from bootstrap |
   | `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER` | from bootstrap |
   | `CERT_MANAGER_CLIENT_ID` | cert-manager service principal (README A6) |
   | optional: `OPENCLAW_MODEL`, `AGENT_NAME`, `ORGANISATION_NAME`, `OPERATOR_NAME` | OpenClaw overrides (README A7) |
   | optional: `ACME_EMAIL` | Let's Encrypt contact address |
   | optional: `CI_IMAGE_PREFIX` | default `ghcr.io/<owner>/<repo>/ci-tools` - set it (lowercase) if the repository name has capitals |

   Settings → Environments → **`demo`**: deployment branches "Selected
   branches" → `main` only. Environment **secrets** (same values as the
   GitLab CI/CD variables):

   | Secret | Used by |
   |---|---|
   | `CERT_MANAGER_CLIENT_SECRET` | observability stack |
   | `GRAFANA_ADMIN_PASSWORD` | observability stack |
   | `OPENCLAW_HOOKS_TOKEN` | observability stack, aiops |
   | `OPENCLAW_GATEWAY_TOKEN` | tenants, aiops |
   | `ANTHROPIC_SETUP_TOKEN` | aiops |

4. **Self-hosted runner.** On the management VM (next to the GitLab
   runner), with a registration token from Settings → Actions → Runners →
   New self-hosted runner:

   ```bash
   GITHUB_REPO=<owner>/<repo> RUNNER_TOKEN=<token> RUNNER_COUNT=2 ./bootstrap/github-runner.sh
   ```

5. **CI images.** Run the *CI images* workflow once (it also runs on
   every change under `ci/images/`). Then Packages → each `ci-tools/*`
   package → Package settings → change visibility to **public** (pull
   requests from forks can then run the rule tests too).
6. **Pages.** Settings → Pages → Source "GitHub Actions"; run the
   *Pages* workflow once. Create the label `self-service`.
7. **Optional: GitHub App for self-service pull requests.** Pull
   requests opened with the workflow's own `GITHUB_TOKEN` do not trigger
   other workflows, so CI does not run on them automatically (close and
   reopen the PR to start it). To avoid that, create a GitHub App with
   Contents + Pull requests write, install it on the repository and set
   variable `SELF_SERVICE_APP_ID` and secret `SELF_SERVICE_APP_PRIVATE_KEY`.
   If a request fails after its branch was created, delete the branch
   before re-running it.
8. **Rebuild.** Actions → *Deploy* → Run workflow → scope `everything`.

## Local Terraform

```bash
az login
export ARM_USE_AZUREAD=true TFSTATE_RESOURCE_GROUP=... TFSTATE_STORAGE_ACCOUNT=... TFSTATE_CONTAINER=tfstate
export TF_VAR_resource_group_name=<resource-group> TF_VAR_dns_zone_name=<dns-zone>
ci/scripts/tf-init.sh demo && terraform -chdir=terraform/environments/demo plan
```

Your user needs "Storage Blob Data Contributor" on the state storage
account (bootstrap grants it to whoever runs it).

## Known differences to the GitLab pipeline

- GitLab shows a manual button per job; GitHub has no manual jobs, so
  Deploy/Destroy take a `scope` (and `systems`) input instead.
- Separate Terraform states: GitHub keeps state in Azure Storage, GitLab
  in its own HTTP state backend (`ci/gitlab/http-backend-override.sh`).
  Use one platform per environment at a time - both would otherwise
  manage the same Azure resources from different states.
- The Key Vault of the observability stack is only soft-deleted on
  destroy (`purge_soft_delete_on_destroy = false`): purging needs a
  subscription-level permission neither pipeline identity has. It
  expires after 7 days; a rebuild uses a new name.
- Tenant rollouts (push to `main`) are serialized with each other, not
  with Deploy/Destroy: don't merge tenant changes while a Destroy runs.
