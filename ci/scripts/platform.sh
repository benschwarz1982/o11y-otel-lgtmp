#!/usr/bin/env bash
# Plan/apply/destroy one platform component. Secrets and TF_VAR_* come
# from the workflow environment (GitHub environment "demo").
#
#   ci/scripts/platform.sh <infra|observability-stack|aiops|tenants> <plan|apply|destroy>
set -euo pipefail

component="${1:?usage: platform.sh <component> <plan|apply|destroy>}"
action="${2:?usage: platform.sh <component> <plan|apply|destroy>}"
here="$(dirname "$0")"

tf() { # <environment> <action>
  "${here}/tf-init.sh" "$1"
  case "$2" in
    plan)    terraform -chdir="terraform/environments/$1" plan -input=false -lock-timeout=5m ;;
    apply)   terraform -chdir="terraform/environments/$1" apply -input=false -lock-timeout=5m -auto-approve ;;
    destroy) terraform -chdir="terraform/environments/$1" destroy -input=false -lock-timeout=5m -auto-approve ;;
    *) echo "Unknown action: $2" >&2; exit 1 ;;
  esac
}

# Optional OpenClaw overrides: only passed when set, so the Terraform
# defaults apply otherwise.
[ -n "${OPENCLAW_MODEL:-}" ] && export TF_VAR_openclaw_model="${OPENCLAW_MODEL}"
[ -n "${AGENT_NAME:-}" ] && export TF_VAR_openclaw_agent_name="${AGENT_NAME}"
[ -n "${ORGANISATION_NAME:-}" ] && export TF_VAR_openclaw_organisation_name="${ORGANISATION_NAME}"
[ -n "${OPERATOR_NAME:-}" ] && export TF_VAR_openclaw_operator_name="${OPERATOR_NAME}"

case "${component}" in
  infra)
    tf demo "${action}"
    ;;
  observability-stack)
    # Two states: the CRs need the CRDs the stack's Helm releases install,
    # so apply stack -> crs and destroy in reverse.
    if [ "${action}" = destroy ]; then
      tf observability-stack-crs destroy
      tf observability-stack destroy
    else
      tf observability-stack "${action}"
      # The crs plan needs the stack's CRDs - skip it on a plan-only run
      # against an empty cluster.
      if [ "${action}" = apply ] || kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
        tf observability-stack-crs "${action}"
      fi
    fi
    ;;
  aiops)
    tf aiops "${action}"
    ;;
  tenants)
    # Only destroy here - apply goes through ci/scripts/tenants-rollout.sh
    # (Helm tenant overrides + newest-wins guard + rule sync).
    [ "${action}" = destroy ] || { echo "tenants: use tenants-rollout.sh for ${action}" >&2; exit 1; }
    tf tenants destroy
    ;;
  *)
    echo "Unknown component: ${component}" >&2
    exit 1
    ;;
esac
