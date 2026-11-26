# Pre-built CI images for this pipeline's azure-cli-based jobs - replaces
# the per-run tdnf/curl bootstrap the `.install_tools`/`.install_terraform`/
# `.install_ansible`/`.install_ansible_windows` templates used to do inside
# every single job (see .gitlab-ci.yml's own git history). Found live:
# `tdnf install git` alone pulled in ~60 Perl packages (~25.6 MB download,
# ~60 MB installed) on every job run, purely to silence a cosmetic
# get-helm-3 warning this repo never actually triggers (no `helm plugin
# install` anywhere) - on top of a fresh 49 MB kubectl download and a
# `curl | bash` helm install, also every run. Measured cost on a real
# `demo:uc1-break` run: 2:38 total, nearly all of it this bootstrap.
#
# Four named build targets, layered so common tools are shared - built/
# pushed by the `build:ci-image-*` jobs in .gitlab-ci.yml (stage
# "ci-images", only on a real change to this file):
#
#   base             kubectl + helm on top of the azure-cli image
#   terraform        base + terraform
#   ansible-linux    terraform + ansible-core + openssh-client
#   ansible-windows  terraform + ansible-core + pywinrm + ansible.windows
#
# Every job that previously referenced `.install_tools`/`.install_ssh`/
# `.install_terraform`/`.install_ansible`/`.install_ansible_windows` now
# just uses the matching image below instead - see that job's own
# `image:` line in .gitlab-ci.yml. `.setup_kubeconfig` (az login/az aks
# get-credentials) is NOT covered here - it's dynamic per-job
# authentication, not a package install, and stays a runtime script step
# in every consuming job, unchanged.
#
# Versions are pinned exactly as they were in the job scripts this
# replaces (kubectl/helm/terraform), or exactly as verified live against
# a real successful pipeline run (ansible-core/pywinrm - see the comment
# on the ansible-linux/ansible-windows stages below) - same "always pin
# an exact version, never float" convention this whole file already
# uses throughout.

FROM mcr.microsoft.com/azure-cli:2.93.0-azurelinux4.0 AS base

# Azure Linux 4 (GA 2026-11-17): tdnf is a symlink to dnf5 there, so the
# tdnf calls below keep working. `tdnf -y upgrade` first: the base image
# lags behind the distro's security updates (trivy, build:ci-image-scan,
# found fixed .azl packages for curl/openssl/python3/... on every build).
#
# kubectl, helm and terraform come from pinned release downloads, each
# checked against the SHA256 file published with that release - no
# `curl | bash` installer. The checksums are fetched, not hard-coded, so
# a version bump is a one-line ARG change. tar/gzip
# unpack the helm archive (gzip is not in the Azure Linux 4 image); gawk:
# awk in the CI job scripts. kubectl 1.37: AKS runs 1.36, within
# kubectl's +/-1 minor version-skew policy. helm 4: the Terraform helm
# provider embeds its own helm library; this CLI is only used by
# tenants:rollout (helm get metadata / helm upgrade --reuse-values).
ARG KUBECTL_VERSION=1.37.3
ARG HELM_VERSION=4.3.2
RUN tdnf -y upgrade \
    && tdnf install -y tar gzip gawk \
    && tdnf clean all \
    && cd /tmp \
    && curl -fsSLO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && echo "$(curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256")  kubectl" | sha256sum -c - \
    && install -m 0755 kubectl /usr/local/bin/kubectl \
    && curl -fsSLO "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    && curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" | sha256sum -c - \
    && tar -xzf "helm-v${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64/helm \
    && install -m 0755 linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/kubectl /tmp/helm-*.tar.gz /tmp/linux-amd64

FROM base AS terraform

# python3-pyyaml: scripts/sync-mimir-rules.py (tenants:rollout) and
# scripts/generate-rules.py / test-rules.py (validate:rules) - the
# azure-cli image's system python has no YAML module.
ARG TERRAFORM_VERSION=1.17.2
RUN tdnf install -y unzip python3-pyyaml \
    && cd /tmp \
    && curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" \
      | grep " terraform_${TERRAFORM_VERSION}_linux_amd64.zip$" | sha256sum -c - \
    && mv "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" /tmp/terraform.zip \
    && unzip -q /tmp/terraform.zip -d /usr/local/bin \
    && rm -f /tmp/terraform.zip \
    && tdnf clean all

# G03/G04: Sloth (OpenSLO -> Prometheus rules) and promtool (rule checks
# and unit tests), copied from their pinned official images instead of
# downloading release archives. Keep SLOTH_IMAGE/PROMTOOL_IMAGE in scripts/generate-rules.py
# and scripts/test-rules.py in sync (used for local runs via docker).
COPY --from=ghcr.io/slok/sloth:v0.16.0 /usr/local/bin/sloth /usr/local/bin/sloth
COPY --from=prom/prometheus:v3.16.0 /bin/promtool /usr/local/bin/promtool

FROM terraform AS ansible-linux

# ansible-core installs into a dedicated venv at /opt/ansible-venv, NOT
# straight into the image's system Python - corrected after a real pip
# warning on the first live build ("Running pip as the 'root' user can
# result in broken permissions and conflicting behaviour with the
# system package manager"), and a real question about it: this image's
# base is mcr.microsoft.com/azure-cli, which ships its OWN Python
# install with its own PyYAML/etc. dependencies - a global `pip
# install ansible-core` (which drags in its own PyYAML, cryptography,
# jinja2...) risks silently overwriting whatever az CLI itself depends
# on, breaking `az login`/`az aks get-credentials` in every job that
# uses this image (every one of them, via .setup_kubeconfig). A
# Dockerfile build DOES have a shared/reused interpreter to protect
# after all - same reasoning .gitlab-ci.yml's own job-level pip-install
# convention already uses (every *job* that runs "pip install" creates
# a venv first, see that file's top-of-file comment), just applied at
# image-build time instead. PATH is extended via ENV so consuming jobs
# can still call `ansible-playbook`/`ansible-galaxy` directly, with no
# activation step of their own.
#
# python3-pip isn't preinstalled in the azure-cli base image - confirmed
# live via a real deploy-instrumentations:1286-linux-basis pipeline run
# (its own .install_ansible step had to tdnf-install it every time, same
# as this). No separate python3-venv package here, unlike the
# Debian/Ubuntu case that old .install_ansible script's own
# multi-distro fallback was guarding against - found live: tdnf has no
# such package on this distro ("python3-venv package not found or not
# installed... No matching packages") - Azure Linux's python3 bundles
# the venv module in the core package already, so `python3 -m venv`
# just works without it.
# ansible-core==2.22.0 - latest stable on PyPI as of this pin (bumped
# from the 2.21.3 a live build of this image originally resolved via
# Kaniko's own log - see the header comment above for why that
# original pin couldn't be read from a past job's log instead).
RUN tdnf install -y openssh-clients python3-pip \
    && tdnf clean all \
    && python3 -m venv /opt/ansible-venv \
    && /opt/ansible-venv/bin/pip install --quiet --upgrade pip \
    && /opt/ansible-venv/bin/pip install ansible-core==2.22.0
ENV PATH="/opt/ansible-venv/bin:${PATH}"

FROM terraform AS ansible-windows

# Same venv rationale as ansible-linux above. ansible.windows is pinned
# exactly - found live in an earlier session: an unpinned install
# silently picked up 3.8.0 and broke WinRM entirely ("Unable to execute
# ssh command line on a controller: No such file or directory: b'ssh'",
# Ansible falling back to the ssh connection plugin instead of winrm).
# 3.9.2 together with ansible-core 2.22 - verify with
# deploy-instrumentations:1229-windows-basis after every bump; 3.7.0 is
# the last version confirmed working with ansible-core 2.21.
# Same no-python3-venv-package note as ansible-linux above.
# ansible-core==2.22.0/pywinrm==0.5.0 - same live-verified pin as
# ansible-linux's own ansible-core comment. certifi pinned explicitly:
# pywinrm pulls it in via requests, and the resolved version carried a
# CRITICAL advisory (trivy, fixed in 2026.10.18).
# The collection goes to the system-wide collections path, not ~/.ansible:
# GitHub Actions container jobs run with HOME=/github/home.
RUN tdnf install -y python3-pip \
    && tdnf clean all \
    && python3 -m venv /opt/ansible-venv \
    && /opt/ansible-venv/bin/pip install --quiet --upgrade pip \
    && /opt/ansible-venv/bin/pip install ansible-core==2.22.0 pywinrm==0.5.0 certifi==2026.10.23 \
    && /opt/ansible-venv/bin/ansible-galaxy collection install ansible.windows:3.9.2 --force -p /usr/share/ansible/collections
ENV PATH="/opt/ansible-venv/bin:${PATH}"
