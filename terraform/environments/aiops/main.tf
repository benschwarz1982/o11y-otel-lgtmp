data "azurerm_kubernetes_cluster" "main" {
  name                = var.aks_cluster_name
  resource_group_name = var.resource_group_name
}

data "azurerm_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = var.resource_group_name
}

# Reads the already-running Traefik Service (observability-stack's own
# helm_release.traefik, guaranteed to already exist and be stable by the
# time this state applies - deploy-aiops's own stage runs after
# deploy-fleets/deploy-instrumentations, well after deploy:observability-stack).
# No time_sleep wait needed here the way observability-stack's own
# grafana DNS record has one - that one runs right after Traefik's own
# first-ever install in the same apply; this one never does.
data "kubernetes_service_v1" "traefik" {
  metadata {
    name      = "traefik"
    namespace = "ingress-traefik"
  }
}

# Traefik runs with hostNetwork: true (helm/values/traefik-values.yaml) -
# its effective source IP for any request it forwards is one of this
# cluster's node IPs, not a regular pod IP. Found live: with Azure CNI,
# nodes and pods share the same flat VNet subnet, so there is no CIDR
# that contains only Traefik and no other pod - trusting the whole
# subnet as a proxy (OpenClaw's gateway.trustedProxies) let any other
# pod (e.g. Grafana calling OpenClaw's webhook directly) be
# misclassified as an unverifiable proxy hop and rejected with 403
# proxy_attribution_required. Node IPs are the one identity in this
# topology that's genuinely disjoint from every regular pod's IP, and
# computing them here (rather than hardcoding today's values) means
# trustedProxies self-corrects on every apply if the node pool is ever
# resized or its nodes replaced - the only residual gap is a node
# change that happens between two applies of this state, not something
# this demo's node pool (fixed size, no autoscaler) does on its own.
data "kubernetes_nodes" "all" {}

locals {
  node_internal_ips = [
    for node in data.kubernetes_nodes.all.nodes : [
      for addr in node.status[0].addresses : addr.address
      if addr.type == "InternalIP"
    ][0]
  ]
}

# ---------------------------------------------------------------------------
# OpenClaw (README Open Points - ai-ops-azure integration) - an LLM-based
# SRE remediation agent (Claude via the Claude Pro/Max subscription's
# setup-token, see the ANTHROPIC_OAUTH_TOKEN env below), migrated from the
# separate ai-ops-azure repo/VMs onto this cluster. Reacts to UC1's
# existing "1286 Linux Basis - host CPU > 80%" alert (Grafana webhook
# contact point, alerting/shared/openclaw-webhook.yaml) and remediates
# vm-rocky-demo over SSH, following a runbook automatically when one
# matches (repo-level /sre/runbooks/, extensible - see
# kubernetes_config_map_v1.openclaw_runbooks below) or falling back to
# human-in-the-loop otherwise - see openclaw/workspace-templates/
# AGENTS.md's own "## Tools" section's search-order rules (consolidated
# there from a formerly separate TOOLS.md - see that section's own
# comment for why).
#
# Own dedicated Terraform state and CI jobs (deploy:aiops/destroy:aiops) -
# and its own Kubernetes namespace ("openclaw", not observability-stack's
# "observability") - so the AI/OpenClaw component of the demo can be
# deployed/destroyed independently of the rest of the observability
# stack. The one thing this namespace split changes functionally is the
# ingress NetworkPolicy below, which now needs a namespace_selector
# alongside its pod_selector to keep allowing Grafana (a different
# namespace's pod) through.
#
# No Helm chart exists for OpenClaw anywhere upstream (checked every repo
# in the openclaw GitHub org) - plain kubernetes_* resources instead,
# same idiom as observability-stack's own
# kubernetes_cron_job_v1.ingestion_midnight_snapshot (mount a script/
# config into a stock/upstream image, no custom build).
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "openclaw" {
  metadata {
    name = "openclaw"
  }
}

# Dedicated SSH key for OpenClaw's remediation access to vm-rocky-demo -
# deliberately NOT the same key terraform/environments/fleet-1286-linux-
# basis's own state generates for Ansible: reading it here would need a
# live cross-state Terraform read, coupling two otherwise-independent CI
# jobs for no reason (see that state's own backend.tf comment on why its
# state is kept separate in the first place). Self-contained instead:
# mint our own key in this state, push its public half onto the VM via
# azurerm_virtual_machine_run_command - a native azurerm-provider
# resource (available since provider v3.88.0, well under this file's
# `~> 5.0` pin), not a local-exec/az-CLI workaround - this job's own
# container image (hashicorp/terraform) has no az CLI installed.
resource "tls_private_key" "openclaw_ssh" {
  algorithm = "ED25519"
}

# Generic azurerm_virtual_machine data source (not the linux-specific
# resource type - there's no matching "linux"/"windows" data source,
# only this one) - also exposes private_ip_address directly, so no
# separate azurerm_network_interface lookup is needed for that either.
# A live lookup, not a deterministic ID construction - this state's
# "deploy-aiops" CI stage runs after deploy-fleets/deploy-instrumentations
# (see .gitlab-ci.yml), so vm-rocky-demo is guaranteed to already exist
# by the time this applies, as long as fleet-1286-linux-basis was
# triggered at some point. If it wasn't, this whole state's plan/apply
# fails outright ("was not found") - a legitimate signal that fleet was
# skipped, not a bug to design around.
data "azurerm_virtual_machine" "vm_rocky_demo" {
  name                = "vm-rocky-demo"
  resource_group_name = var.resource_group_name
}

# F07: OpenClaw logs in as its own unprivileged user "openclaw" - not as
# the VM's admin "rocky", which has unrestricted passwordless sudo. Its
# only root privilege is one wrapper, /usr/local/sbin/demo-uc1-stop
# (sudoers: exactly that path, no arguments), which stops just the
# demo:uc1-break CPU-spin loops: PIDs from the root-owned pid file whose
# process is root-owned and whose command line is exactly that loop.
# Everything else in the runbook (top, cat, /proc checks) needs no
# privileges. That "only runbook commands" holds is therefore enforced
# by the VM, no longer just a rule in OpenClaw's prompt. "restrict" in
# authorized_keys disables port/agent/X11 forwarding and PTYs.
#
# The key lives in a root-owned file (/etc/ssh/authorized_keys.d/openclaw,
# added to sshd's AuthorizedKeysFile via a drop-in), never in openclaw's
# own home: this script runs as root on every re-apply, and writing into
# a directory openclaw controls would follow a symlink it planted there.
#
# Also removes the key from rocky's authorized_keys, where earlier
# versions of this script installed it.
locals {
  openclaw_ssh_public_key = trimspace(tls_private_key.openclaw_ssh.public_key_openssh)

  demo_uc1_stop = <<-EOT
    #!/bin/bash
    # Managed by terraform/environments/aiops (F07) - stops only the
    # demo:uc1-break CPU-spin loops. Run by OpenClaw via sudo.
    set -u
    f=/tmp/demo-uc1-cpu.pids
    want=$(printf 'bash\0-c\0while :; do :; done\0' | od -An -tx1 | tr -d ' \n')
    is_loop() {
      [ -d "/proc/$1" ] || return 1
      [ "$(stat -c %u "/proc/$1")" = 0 ] || return 1
      [ "$(od -An -tx1 "/proc/$1/cmdline" 2>/dev/null | tr -d ' \n')" = "$want" ]
    }
    if [ ! -e "$f" ]; then echo "no pid file - nothing to stop"; exit 0; fi
    if [ -L "$f" ] || [ ! -f "$f" ] || [ "$(stat -c %u "$f")" != 0 ]; then
      echo "refusing: $f is not a regular root-owned file"; exit 1
    fi
    pids=$(grep -E '^[0-9]+$' "$f")
    for pid in $pids; do
      if is_loop "$pid"; then kill "$pid" && echo "$pid: killed"
      elif [ -d "/proc/$pid" ]; then echo "$pid: not a demo CPU-spin loop - left alone"
      else echo "$pid: already gone"; fi
    done
    sleep 1
    for pid in $pids; do
      if is_loop "$pid"; then echo "WARNING: CPU-spin loop $pid is still running"; exit 1; fi
    done
    rm -f "$f"
    echo "stopped - verified no CPU-spin loop remains"
  EOT
}

resource "azurerm_virtual_machine_run_command" "openclaw_ssh_key" {
  name               = "install-openclaw-ssh-key"
  location           = data.azurerm_virtual_machine.vm_rocky_demo.location
  virtual_machine_id = data.azurerm_virtual_machine.vm_rocky_demo.id

  source {
    script = <<-EOT
      set -eu
      id openclaw >/dev/null 2>&1 || useradd -m -s /bin/bash openclaw
      install -d -m 755 -o root -g root /etc/ssh/authorized_keys.d
      tmp=$(mktemp /etc/ssh/authorized_keys.d/.openclaw.XXXXXX)
      echo 'restrict ${local.openclaw_ssh_public_key}' > "$tmp"
      chmod 644 "$tmp"
      mv -f "$tmp" /etc/ssh/authorized_keys.d/openclaw
      echo 'AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys.d/%u' > /etc/ssh/sshd_config.d/40-authorized-keys-d.conf
      restorecon -R /etc/ssh/authorized_keys.d /etc/ssh/sshd_config.d 2>/dev/null || true
      sshd -t
      systemctl reload sshd
      if [ -f /home/rocky/.ssh/authorized_keys ]; then
        tmp=$(mktemp)
        grep -vF '${local.openclaw_ssh_public_key}' /home/rocky/.ssh/authorized_keys > "$tmp" || true
        cat "$tmp" > /home/rocky/.ssh/authorized_keys
        rm -f "$tmp"
      fi
      echo '${base64encode(local.demo_uc1_stop)}' | base64 -d > /usr/local/sbin/demo-uc1-stop
      chown root:root /usr/local/sbin/demo-uc1-stop
      chmod 755 /usr/local/sbin/demo-uc1-stop
      echo 'openclaw ALL=(root) NOPASSWD: /usr/local/sbin/demo-uc1-stop ""' > /etc/sudoers.d/90-openclaw
      chmod 440 /etc/sudoers.d/90-openclaw
      visudo -cf /etc/sudoers.d/90-openclaw >/dev/null
    EOT
  }
}

# F08: vm-rocky-demo's SSH host key, read over the Azure control plane -
# becomes OpenClaw's known_hosts (StrictHostKeyChecking=yes). A run
# command of its own, not the last line of openclaw_ssh_key's script:
# on an in-place update Terraform already knows the PREVIOUS run's output
# at plan time (found live: "" from the old script, so regex() failed
# the plan), while a newly created run command's output stays unknown
# until apply. depends_on serializes the two run commands on the VM.
resource "azurerm_virtual_machine_run_command" "vm_rocky_host_key" {
  name               = "read-ssh-host-key-openclaw"
  location           = data.azurerm_virtual_machine.vm_rocky_demo.location
  virtual_machine_id = data.azurerm_virtual_machine.vm_rocky_demo.id

  source {
    script = "cut -d' ' -f1-2 /etc/ssh/ssh_host_ed25519_key.pub"
  }

  depends_on = [azurerm_virtual_machine_run_command.openclaw_ssh_key]
}

resource "kubernetes_persistent_volume_claim_v1" "openclaw_home" {
  # AKS's "default" StorageClass uses WaitForFirstConsumer binding -
  # the underlying disk isn't actually provisioned until a Pod that
  # mounts this PVC is scheduled (found live: the PVC just sat in
  # "Pending", "waiting for first consumer to be created", forever).
  # The default wait_until_bound = true deadlocks against that: Terraform
  # won't create kubernetes_deployment_v1.openclaw (the one Pod that
  # would satisfy "first consumer") until this PVC resource finishes
  # waiting to bind, which never happens without that Pod. Disabled so
  # Terraform creates the PVC object immediately and moves on to the
  # Deployment, whose Pod scheduling is what actually triggers binding.
  wait_until_bound = false

  metadata {
    name      = "openclaw-home"
    namespace = kubernetes_namespace_v1.openclaw.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        # Demo-sized, not openclaw-app's own 10Gi production sizing -
        # just needs to hold OpenClaw's own generated/mutable state
        # (session history, anything it writes at runtime), not large
        # media/model artifacts - the identity/personality files
        # themselves are static, provided via ConfigMap below, not
        # self-generated.
        storage = "2Gi"
      }
    }
  }
}

resource "kubernetes_config_map_v1" "openclaw_config" {
  metadata {
    name      = "openclaw-config"
    namespace = kubernetes_namespace_v1.openclaw.metadata[0].name
  }
  data = {
    "openclaw.json" = templatefile("${path.module}/../../../openclaw/openclaw.json", {
      openclaw_model       = var.openclaw_model
      trusted_proxies_json = jsonencode(local.node_internal_ips)
    })
    "AGENTS.md" = templatefile("${path.module}/../../../openclaw/workspace-templates/AGENTS.md", {
      openclaw_organisation_name = var.openclaw_organisation_name
      vm_rocky_demo_ip           = data.azurerm_virtual_machine.vm_rocky_demo.private_ip_address
    })
    "SOUL.md" = file("${path.module}/../../../openclaw/workspace-templates/SOUL.md")
    "USER.md" = templatefile("${path.module}/../../../openclaw/workspace-templates/USER.md", {
      openclaw_operator_name     = var.openclaw_operator_name
      openclaw_organisation_name = var.openclaw_organisation_name
    })
    "IDENTITY.md" = templatefile("${path.module}/../../../openclaw/workspace-templates/IDENTITY.md", {
      openclaw_model             = var.openclaw_model
      openclaw_agent_name        = var.openclaw_agent_name
      openclaw_organisation_name = var.openclaw_organisation_name
    })
  }
}

# Separate ConfigMap from openclaw_config above, mounted as a whole
# directory (not per-file subPath mounts) - deliberately extensible:
# every *.md file under /sre/runbooks (repo-level, not nested under
# openclaw/ - shared convention with the original ai-ops-azure repo)
# becomes one key here automatically via fileset(), so adding a new
# runbook is just adding one file and committing it - no Terraform
# change needed, it's picked up the next time this state is applied.
resource "kubernetes_config_map_v1" "openclaw_runbooks" {
  metadata {
    name      = "openclaw-runbooks"
    namespace = kubernetes_namespace_v1.openclaw.metadata[0].name
  }
  data = {
    for f in fileset("${path.module}/../../../sre/runbooks", "*.md") :
    f => file("${path.module}/../../../sre/runbooks/${f}")
  }
}

resource "kubernetes_secret_v1" "openclaw" {
  metadata {
    name      = "openclaw-secrets"
    namespace = kubernetes_namespace_v1.openclaw.metadata[0].name
  }
  data = {
    ANTHROPIC_SETUP_TOKEN = var.anthropic_setup_token
    # A plain variable, not a random_password generated here - Grafana's
    # webhook contact point (terraform/environments/tenants, a separate
    # Terraform state) needs this same value to authenticate to
    # OpenClaw's gateway, and generating it in one state then reading it
    # from the other would need a live cross-state Terraform read (the
    # same kind of unnecessary job coupling avoided for the SSH key
    # above). A shared CI/CD variable, exported as TF_VAR_
    # openclaw_gateway_token in both states' init scripts, is simpler -
    # same pattern as anthropic_setup_token.
    OPENCLAW_GATEWAY_TOKEN = var.openclaw_gateway_token
    # F05/NFR-03: referenced from openclaw.json as ${OPENCLAW_HOOKS_TOKEN}
    # (OpenClaw's own config env substitution) instead of being rendered
    # into the openclaw-config ConfigMap.
    OPENCLAW_HOOKS_TOKEN = var.openclaw_hooks_token
    id_rsa               = tls_private_key.openclaw_ssh.private_key_openssh
    # F08: vm-rocky-demo's host key (azurerm_virtual_machine_run_command.vm_rocky_host_key).
    known_hosts = "${data.azurerm_virtual_machine.vm_rocky_demo.private_ip_address} ${regex("ssh-ed25519 [A-Za-z0-9+/=]+", azurerm_virtual_machine_run_command.vm_rocky_host_key.instance_view[0].output)}\n"
  }
}

resource "kubernetes_deployment_v1" "openclaw" {
  metadata {
    name      = "openclaw"
    namespace = kubernetes_namespace_v1.openclaw.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "openclaw"
    }
  }
  spec {
    replicas = 1
    # Recreate, not the default RollingUpdate: a RollingUpdate can never actually complete against a
    # single ReadWriteOnce PVC, since the new pod can't attach the
    # already-in-use volume until the old one is killed, but the old one
    # is never killed until the new one is ready - a deadlock.
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "openclaw"
      }
    }
    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "openclaw"
        }
        # Neither ConfigMap this Deployment mounts auto-refreshes a
        # running Pod on its own: openclaw_config is mounted via
        # subPath (subPath mounts never pick up a ConfigMap update
        # without a Pod restart - a known Kubernetes limitation, not
        # specific to this setup), and openclaw_runbooks is only ever
        # read once, at Pod startup, by the runbooks-derefencer init
        # container above. Without this annotation, editing a runbook
        # or AGENTS.md and re-running deploy-aiops would silently leave
        # the already-running Pod on the old content - these checksums
        # change whenever either ConfigMap's actual data changes,
        # which changes the Pod template, which is what makes
        # Kubernetes actually roll a new Pod.
        annotations = {
          "checksum/openclaw-config"   = sha256(jsonencode(kubernetes_config_map_v1.openclaw_config.data))
          "checksum/openclaw-runbooks" = sha256(jsonencode(kubernetes_config_map_v1.openclaw_runbooks.data))
          # Same idea for the setup-token: env values from a Secret are
          # only read at container start, so a rotated or removed token
          # must roll the Pod. A SHA-256 of a long random token reveals
          # nothing usable.
          "checksum/anthropic-setup-token" = sha256(var.anthropic_setup_token)
          # Same for both gateway tokens (F15): neither is in a ConfigMap
          # anymore, so without these a rotation wouldn't restart the Pod.
          "checksum/openclaw-gateway-token" = sha256(var.openclaw_gateway_token)
          "checksum/openclaw-hooks-token"   = sha256(var.openclaw_hooks_token)
        }
      }
      spec {
        # fs_group chowns the mounted PVC to this GID on attach - without
        # it, the Azure Disk CSI driver formats openclaw-home owned by
        # root, and the container's own UID 1000 (see the container's
        # security_context below) can't write to it. Found live: "EACCES:
        # permission denied, mkdir '/home/node/.openclaw/state'" - the
        # app's own on-disk state directory, created on first startup.
        # fs_group stays for the ssh-key Secret (id_rsa 0600 is readable to
        # UID 1000 only through this group), but on the PVC it also adds
        # group bits and setgid to every directory on each mount - and
        # OpenClaw >= 2026.11 (@openclaw/fs-safe) refuses any private
        # directory with group/other bits or setgid (mode & 0o7077). Found
        # live: "Doctor stopped ... FsSafeError: created directory
        # admission failed". The home-permissions init container below
        # undoes that after every mount.
        security_context {
          fs_group = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        # Runs as root on purpose, limited to CHOWN (volume root is created
        # root-owned by the Azure Disk CSI driver), FOWNER (chmod on files
        # it doesn't own) and DAC_READ_SEARCH (traverse 0700 directories):
        # hands the whole PVC to UID 1000 and makes it private again.
        # Symbolic g-s/u-s, not an octal mode: GNU chmod keeps setgid on
        # directories for a plain octal mode like 700.
        init_container {
          name    = "home-permissions"
          image   = "ghcr.io/openclaw/openclaw:2026.11.10"
          command = ["sh", "-c", "chown -R 1000:1000 /openclaw-home && find /openclaw-home -type d -exec chmod u+rwx,go-rwx,ug-s,a-t {} + && find /openclaw-home -type f -exec chmod go-rwx,ug-s,a-t {} +"]
          security_context {
            run_as_non_root            = false
            run_as_user                = 0
            run_as_group               = 0
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
              add  = ["CHOWN", "FOWNER", "DAC_READ_SEARCH"]
            }
          }
          volume_mount {
            name       = "home"
            mount_path = "/openclaw-home"
          }
        }
        # openclaw.json is copied onto the PVC on every start instead of a
        # subPath mount: OpenClaw >= 2026.11's doctor rewrites the config
        # atomically (temp file + rename), and a rename onto a mount point
        # fails - found live: "EBUSY: resource busy or locked, rename
        # '.fs-safe-replace...tmp' -> '/home/node/.openclaw/openclaw.json'".
        # The ConfigMap stays the source of truth: whatever the doctor
        # migrates in place is overwritten again on the next Pod start.
        init_container {
          name    = "config-copy"
          image   = "ghcr.io/openclaw/openclaw:2026.11.10"
          command = ["sh", "-c", "cp /config-src/openclaw.json /openclaw-home/openclaw.json && chmod 0600 /openclaw-home/openclaw.json"]
          security_context {
            run_as_non_root            = true
            run_as_user                = 1000
            run_as_group               = 1000
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
          volume_mount {
            name       = "config"
            mount_path = "/config-src"
            read_only  = true
          }
          volume_mount {
            name       = "home"
            mount_path = "/openclaw-home"
          }
        }
        # Found live: OpenClaw's own "read" tool refuses to read a
        # ConfigMap-mounted file directly ("path must be a regular
        # file") - Kubernetes always mounts a ConfigMap volume's files
        # as symlinks through an atomically-swapped "..data" directory
        # (so updates apply without partial-write races), never as
        # plain regular files. AGENTS.md's own runbook-lookup
        # instructions explicitly tell the agent to use the Read tool
        # for this exact path, so this isn't a rare edge case - it
        # reliably breaks the very first step of automatic remediation.
        # This init container dereferences the ConfigMap mount into
        # real regular files on a plain emptyDir once at Pod startup
        # (cp -L follows symlinks and copies their actual content) -
        # the runbooks ConfigMap itself keeps discovering *.md files
        # automatically via fileset() (kubernetes_config_map_v1.
        # openclaw_runbooks below), so adding a new runbook still needs
        # no Terraform change, only a new Pod (which any new
        # deploy-aiops apply that changes this ConfigMap's contents
        # triggers anyway, since the Deployment's own pod template
        # doesn't otherwise change).
        init_container {
          name    = "runbooks-derefencer"
          image   = "ghcr.io/openclaw/openclaw:2026.11.10"
          command = ["sh", "-c", "cp -rL /runbooks-src/. /runbooks-real/"]
          security_context {
            run_as_non_root            = true
            run_as_user                = 1000
            run_as_group               = 1000
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
          volume_mount {
            name       = "runbooks-src"
            mount_path = "/runbooks-src"
            read_only  = true
          }
          volume_mount {
            name       = "runbooks"
            mount_path = "/runbooks-real"
          }
        }
        container {
          name = "openclaw"
          # Pinned to an exact release, not :latest - matches this
          # repo's own "always pin an exact version" convention
          # (ci/images/Dockerfile) and avoids an unannounced behavior
          # change landing on the next unrelated pod restart/rollout.
          image = "ghcr.io/openclaw/openclaw:2026.11.10"

          # Claude subscription setup-token (README A7). OpenClaw's
          # built-in anthropic provider picks it up from this env var as
          # an OAuth credential (`openclaw models status`: "effective=
          # env:OAuth") - nothing is written to the auth store on the PVC,
          # so clearing the CI/CD variable really removes it on the next
          # Pod start. Deliberately not the openclaw-app reference's
          # init-container `models auth paste-token` registration: that
          # persists the token on the PVC, would write it into
          # openclaw.json (re-copied from the ConfigMap on every start
          # here), and `models auth logout` could not remove it again in
          # local tests.
          env {
            name = "ANTHROPIC_OAUTH_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.openclaw.metadata[0].name
                key  = "ANTHROPIC_SETUP_TOKEN"
              }
            }
          }
          env {
            name = "OPENCLAW_GATEWAY_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.openclaw.metadata[0].name
                key  = "OPENCLAW_GATEWAY_TOKEN"
              }
            }
          }
          env {
            name = "OPENCLAW_HOOKS_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.openclaw.metadata[0].name
                key  = "OPENCLAW_HOOKS_TOKEN"
              }
            }
          }
          env {
            name  = "OPENCLAW_GATEWAY_BIND"
            value = "lan"
          }
          env {
            name  = "OPENCLAW_GATEWAY_HOST"
            value = "0.0.0.0"
          }
          env {
            name  = "OPENCLAW_SKIP_ONBOARDING"
            value = "true"
          }
          env {
            name  = "GIT_SSH_COMMAND"
            value = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
          }

          port {
            name           = "gateway"
            container_port = 18789
          }

          # Kubernetes Pod Security Standards "restricted" profile -
          # openclaw-app's own reference manifest was missing the
          # explicit runAsNonRoot, added here for full compliance.
          # run_as_user/run_as_group are required alongside
          # run_as_non_root here specifically because this image's own
          # Dockerfile sets USER node (a name, not a numeric UID) -
          # found live: "container has runAsNonRoot and image has
          # non-numeric user (node), cannot verify user is non-root".
          # Kubernetes can only verify non-root from the image's own
          # metadata when it's a plain integer, so it has to be pinned
          # explicitly instead - 1000 is the standard node/UID GID for
          # the official Node.js Docker images' own "node" user, which
          # this image is built from.
          security_context {
            run_as_non_root            = true
            run_as_user                = 1000
            run_as_group               = 1000
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 18789
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 18789
            }
            initial_delay_seconds = 20
            period_seconds        = 30
          }

          volume_mount {
            name       = "home"
            mount_path = "/home/node/.openclaw"
          }
          volume_mount {
            name       = "config"
            mount_path = "/home/node/.openclaw/workspace/AGENTS.md"
            sub_path   = "AGENTS.md"
          }
          volume_mount {
            name       = "config"
            mount_path = "/home/node/.openclaw/workspace/IDENTITY.md"
            sub_path   = "IDENTITY.md"
          }
          volume_mount {
            name       = "config"
            mount_path = "/home/node/.openclaw/workspace/SOUL.md"
            sub_path   = "SOUL.md"
          }
          volume_mount {
            name       = "config"
            mount_path = "/home/node/.openclaw/workspace/USER.md"
            sub_path   = "USER.md"
          }
          volume_mount {
            name       = "runbooks"
            mount_path = "/home/node/.openclaw/workspace/runbooks"
          }
          volume_mount {
            name       = "ssh-key"
            mount_path = "/home/node/.ssh"
            read_only  = true
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.openclaw_home.metadata[0].name
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.openclaw_config.metadata[0].name
          }
        }
        # ConfigMap-backed source (symlinks) - only the init container
        # above reads from this one; the main container never mounts it
        # directly (see that init container's own comment for why).
        volume {
          name = "runbooks-src"
          config_map {
            name = kubernetes_config_map_v1.openclaw_runbooks.metadata[0].name
          }
        }
        # Plain emptyDir the init container copies real (non-symlink)
        # files into - this is what the main container and OpenClaw's
        # own "read" tool actually see at workspace/runbooks.
        volume {
          name = "runbooks"
          empty_dir {}
        }
        volume {
          name = "ssh-key"
          secret {
            secret_name = kubernetes_secret_v1.openclaw.metadata[0].name
            items {
              key  = "id_rsa"
              path = "id_rsa"
              mode = "0600"
            }
            items {
              key  = "known_hosts"
              path = "known_hosts"
              mode = "0644"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "openclaw" {
  metadata {
    name      = "openclaw"
    namespace = kubernetes_namespace_v1.openclaw.metadata[0].name
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "openclaw"
    }
    port {
      port        = 18789
      target_port = 18789
    }
  }
}

# Ingress restricted to Grafana's own pods (webhook contact point calls)
# and Traefik's own pods (public HTTPS access to the control UI, see
# kubernetes_manifest.openclaw_ingressroute below) - nothing else in the
# cluster, even another pod in this same namespace, should be able to
# reach it. Both run in different namespaces from this one ("openclaw"),
# so each needs a namespace_selector alongside its own pod_selector
# (Kubernetes auto-labels every namespace with kubernetes.io/metadata.name,
# no change needed on either namespace itself) - two separate `from`
# entries, not one, since Terraform's provider represents a NetworkPolicy
# rule's OR-ed sources as a list of `from` blocks, each internally
# AND-matched across its own selectors.
resource "kubernetes_network_policy_v1" "openclaw_ingress" {
  metadata {
    name      = "openclaw-ingress"
    namespace = kubernetes_namespace_v1.openclaw.metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "openclaw"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "observability"
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "grafana"
          }
        }
      }
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "ingress-traefik"
          }
        }
      }
      # Traefik runs with hostNetwork: true, so its requests come from a
      # node IP, which a namespace_selector never matches (Kubernetes
      # NetworkPolicy semantics for host-network pods). Found when
      # enabling Calico enforcement: only Traefik on the
      # same node as OpenClaw would still have got through. Same node
      # IP list as trusted_proxies_json above, refreshed on every apply
      # of this state - re-apply after nodes are replaced. Also admits
      # other host-network processes on the nodes, as trustedProxies
      # already trusts them.
      dynamic "from" {
        for_each = local.node_internal_ips
        content {
          ip_block {
            cidr = "${from.value}/32"
          }
        }
      }
      ports {
        port     = 18789
        protocol = "TCP"
      }
    }
  }
}

# Egress restricted to: DNS, HTTPS (Anthropic API), and SSH to
# vm-rocky-demo specifically - the proportional middle ground between
# ai-ops-azure's own unrestricted egress and openclaw-app's full
# MITM-proxy/domain-allowlisting approach (not adopted - see README
# Open Points).
#
# Honest limitation, not an oversight: the HTTPS rule isn't scoped to
# api.anthropic.com's IPs - vanilla Kubernetes NetworkPolicy (this
# cluster runs Azure CNI, not a DNS-aware CNI like Cilium) only matches
# on IP/CIDR, never hostname, and pinning a provider's current IPs here
# would silently break the agent whenever they change. This still meaningfully shrinks
# the blast radius versus no policy at all - HTTPS and SSH-to-one-VM
# only, not "any protocol, anywhere."
# DNS is limited to CoreDNS and HTTPS to public addresses (see the
# rules below).
resource "kubernetes_network_policy_v1" "openclaw_egress" {
  metadata {
    name      = "openclaw-egress"
    namespace = kubernetes_namespace_v1.openclaw.metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "openclaw"
      }
    }
    policy_types = ["Egress"]
    # DNS only to the cluster's own CoreDNS - not port 53 anywhere,
    # which would allow DNS tunnelling via any external resolver.
    # Matching the CoreDNS pods also covers queries to the kube-dns
    # Service IP (resolv.conf: 10.2.0.10): Calico evaluates egress after
    # kube-proxy's DNAT, i.e. against the pod IP.
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
    }
    # HTTPS to the internet only (Anthropic API) - the private ranges
    # are excluded, so this no longer reaches in-cluster Services/pods
    # or the peered VNets on 443.
    egress {
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        }
      }
      ports {
        port     = 443
        protocol = "TCP"
      }
    }
    egress {
      to {
        ip_block {
          cidr = "${data.azurerm_virtual_machine.vm_rocky_demo.private_ip_address}/32"
        }
      }
      ports {
        port     = 22
        protocol = "TCP"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Public HTTPS access to OpenClaw's own gateway/control UI
# (openclaw.sre.fs167.ch) - same Traefik IngressRoute + cert-manager
# Certificate pattern as Grafana's (observability-stack-crs), skipped
# entirely when cert-manager isn't configured yet (README A6), same
# guard that pattern already uses - the ClusterIssuer these reference
# doesn't exist without it. Unlike Grafana's own pair, both manifests
# live directly in this state rather than a separate *-crs one: the
# ClusterIssuer/CRDs they depend on are already guaranteed to exist by
# the time this state applies (this job's own "deploy-aiops" stage runs
# after deploy:observability-stack, not alongside its first-ever
# install), so there's no CRD-ordering problem to split across two
# states the way observability-stack/observability-stack-crs originally
# had.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "openclaw_cert" {
  count = var.cert_manager_client_id != "" ? 1 : 0

  manifest = yamldecode(file("${path.module}/../../../k8s/ingress/openclaw-cert.yaml"))
}

resource "kubernetes_manifest" "openclaw_ingressroute" {
  count = var.cert_manager_client_id != "" ? 1 : 0

  manifest   = yamldecode(file("${path.module}/../../../k8s/ingress/openclaw-ingressroute.yaml"))
  depends_on = [kubernetes_manifest.openclaw_cert]
}

resource "azurerm_dns_a_record" "openclaw" {
  count = var.cert_manager_client_id != "" ? 1 : 0

  name                = "openclaw"
  zone_name           = data.azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip]
}
