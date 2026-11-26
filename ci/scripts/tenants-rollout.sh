#!/usr/bin/env bash
# Roll out the tenant configuration of the checked-out commit: Helm
# tenant overrides (Mimir/Loki/Tempo/Pyroscope), the tenants Terraform
# state (datasources, dashboards, gateway CR, alert rules) and the
# Mimir ruler rule groups.
#
# Expects PROVISIONED_SHA and PROVISIONED_ORDER (first-parent commit
# count of main) - see the tenants workflow. Runs serialized (workflow
# concurrency group), so reading and writing the guard ConfigMap here is
# race-free.
set -euo pipefail

: "${PROVISIONED_SHA:?}" "${PROVISIONED_ORDER:?}"
here="$(cd "$(dirname "$0")" && pwd)"

# Newest wins: two merges in quick succession can queue rollouts out of
# order; an older main must not overwrite what a newer one rolled out.
last_order="$(kubectl get configmap tenants-rollout-state -n observability --ignore-not-found -o jsonpath='{.data.commit_order}')"
last_sha="$(kubectl get configmap tenants-rollout-state -n observability --ignore-not-found -o jsonpath='{.data.commit_sha}')"
if [ -n "${last_order}" ] && [ "${PROVISIONED_ORDER}" -lt "${last_order}" ]; then
  echo "Skipping: ${PROVISIONED_SHA} is older than ${last_sha}, which a newer run already started rolling out."
  exit 0
fi
# Record BEFORE changing anything: if this run fails halfway, an older
# queued run must still not overwrite it. Equal order passes (retries).
kubectl create configmap tenants-rollout-state -n observability \
  --from-literal=commit_sha="${PROVISIONED_SHA}" \
  --from-literal=commit_order="${PROVISIONED_ORDER}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Tenant overrides only, never a chart upgrade: each release stays on the
# chart version it already runs (--version), values are layered with
# --reuse-values. Loki/Tempo come from the grafana-community repo.
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana-community https://grafana-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update grafana grafana-community >/dev/null
for spec in mimir:grafana/mimir-distributed loki:grafana-community/loki tempo:grafana-community/tempo-distributed pyroscope:grafana/pyroscope; do
  release="${spec%%:*}"
  chart="${spec#*:}"
  version="$(helm get metadata "${release}" -n observability | awk '/^VERSION:/ {print $2}')"
  if [ -z "${version}" ]; then
    echo "Could not read the deployed chart version of ${release}" >&2
    exit 1
  fi
  if ! helm show chart "${chart}" --version "${version}" >/dev/null 2>&1; then
    chart="grafana/${chart#*/}"
  fi
  helm upgrade "${release}" "${chart}" -n observability --version "${version}" --reuse-values -f "helm/values/${release}-tenant-overrides.yaml"
done

"${here}/tf-init.sh" tenants
terraform -chdir=terraform/environments/tenants apply -input=false -lock-timeout=5m -auto-approve

if [ -z "$(kubectl -n observability get endpoints mimir-ruler -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)" ]; then
  echo "::warning::Mimir ruler not running (observability stack not deployed yet?) - rule sync skipped, re-run the tenants rollout afterwards"
  exit 0
fi
kubectl -n observability port-forward svc/mimir-ruler 18080:8080 >/dev/null 2>&1 &
pf=$!
trap 'kill ${pf} 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do curl -sf http://localhost:18080/ready >/dev/null && break; sleep 2; done
python3 scripts/sync-mimir-rules.py --url http://localhost:18080
