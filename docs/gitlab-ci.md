# GitLab CI (Alternative)

GitHub Actions is the primary pipeline. `.gitlab-ci.yml` is kept as a fully working alternative; this page covers running the project on GitLab.

## Moving the Pipeline to GitLab

1. Import or push the repository into a GitLab project. The
   `.gitlab-ci.yml` runs unchanged; the self-service form switches to
   GitLab mode automatically when served from GitLab Pages
   (`<group>.gitlab.io/<project>`).
2. Register the self-hosted runner (below) and create the GitLab CI
   service principal and CI/CD variables
   ([setup, section A](setup.md#a-one-time-bootstrapping-manual), A3-A7),
   including `AZURE_RESOURCE_GROUP`, `DNS_ZONE` and optionally
   `ACME_EMAIL` - the same names as the GitHub repository variables.
3. Rebuild from zero (`deploy:infra` → ...). Terraform state does not
   move between the platforms: destroy the environment with the
   platform that built it first, or import the resources into the new
   state.

## Self-Hosted GitLab Runner

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
az network vnet create -g <resource-group> -n mgmt-vnet \
  --address-prefix 10.2.0.0/16 \
  --subnet-name mgmt-gitlab-runner-subnet --subnet-prefix 10.2.1.0/24 \
  --location switzerlandnorth
az network public-ip create -g <resource-group> -n mgmt-gitlab-runner-pip --sku Standard
az network nsg create -g <resource-group> -n mgmt-gitlab-runner-nsg
# Source IP(s) allowed to SSH in - not left open to 0.0.0.0/0 (a persistent
# VM host is a standing attack surface, unlike the shared runners' fully
# ephemeral containers, or the demo fleet's own short-lived VMs). Repeat
# this rule (next priority) for every additional IP that needs access -
# e.g. your own, if you'll SSH in directly later.
az network nsg rule create -g <resource-group> --nsg-name mgmt-gitlab-runner-nsg \
  --name AllowSSHInbound --priority 100 --access Allow --direction Inbound \
  --source-address-prefixes <IP>/32 --destination-port-ranges 22 --protocol Tcp
az vm create -g <resource-group> -n vm-gitlab-runner \
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
