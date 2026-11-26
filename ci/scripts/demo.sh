#!/usr/bin/env bash
# Break/fix the four demo use cases (see README "Demo").
#
#   ci/scripts/demo.sh <uc1-break|uc1-fix|uc2-break|uc2-fix|uc3-break|uc3-fix|uc4-break|uc4-fix>
set -euo pipefail

scenario="${1:?usage: demo.sh <ucN-break|ucN-fix>}"
rg="${AZURE_RESOURCE_GROUP:?}"
# Key material and scratch files: removed by ci/scripts/cleanup.sh
tmp="${RUNNER_TEMP:-/tmp}/otel-demo"
mkdir -p "${tmp}"

flagd_slowdown() { # <variant>
  kubectl get configmap flagd-config -n astronomy-shop -o jsonpath='{.data.demo\.flagd\.json}' > "${tmp}/flagd.json"
  python3 - "${tmp}/flagd.json" "$1" <<'PY'
import json, sys
path, variant = sys.argv[1], sys.argv[2]
with open(path) as f:
    d = json.load(f)
d["flags"]["intlShippingSlowdown"]["defaultVariant"] = variant
with open(path, "w") as f:
    json.dump(d, f)
PY
  kubectl create configmap flagd-config -n astronomy-shop --from-file=demo.flagd.json="${tmp}/flagd.json" --dry-run=client -o yaml | kubectl apply -f -
  kubectl rollout restart deployment flagd -n astronomy-shop
  kubectl rollout status deployment flagd -n astronomy-shop --timeout=60s
}

case "${scenario}" in
  uc1-break)
    cat > "${tmp}/uc1-break.sh" <<'SH'
rm -f /tmp/demo-uc1-cpu.pids
for i in 1 2; do
  nohup nice -n 19 bash -c 'while :; do :; done' >/dev/null 2>&1 &
  echo $! >> /tmp/demo-uc1-cpu.pids
done
echo "started:"; cat /tmp/demo-uc1-cpu.pids
SH
    az vm run-command invoke -g "${rg}" -n vm-rocky-demo --command-id RunShellScript --scripts "@${tmp}/uc1-break.sh"
    echo "2 CPU-spin loops started on vm-rocky-demo - '1286 Linux Basis - host CPU > 80%' should fire in ~1-2 min."
    ;;
  uc1-fix)
    cat > "${tmp}/uc1-fix.sh" <<'SH'
if [ -f /tmp/demo-uc1-cpu.pids ]; then
  while read -r pid; do kill "$pid" 2>/dev/null || true; done < /tmp/demo-uc1-cpu.pids
  rm -f /tmp/demo-uc1-cpu.pids
fi
pkill -f 'while :; do :; done' 2>/dev/null || true
sleep 1
if pgrep -f 'while :; do :; done' >/dev/null; then
  echo "WARNING: a CPU-spin loop is still running after kill attempts"
  pgrep -af 'while :; do :; done'
  exit 1
fi
echo "stopped - verified no CPU-spin loop remains"
SH
    az vm run-command invoke -g "${rg}" -n vm-rocky-demo --command-id RunShellScript --scripts "@${tmp}/uc1-fix.sh"
    echo "CPU-spin loops killed. The alert clears on its next evaluation (~1 min)."
    ;;
  uc2-break)
    cat > "${tmp}/uc2-break.ps1" <<'PS'
sc.exe failure Spooler reset= 20 actions= restart/5000
$loopScript = @'
while ($true) {
  Get-CimInstance Win32_Service | Where-Object { $_.Name -eq "Spooler" -and $_.State -eq "Running" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  Start-Sleep -Seconds 30
}
'@
Set-Content -Path C:\demo-uc2-kill-loop.ps1 -Value $loopScript
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\demo-uc2-kill-loop.ps1" -WindowStyle Hidden
PS
    az vm run-command invoke -g "${rg}" -n vm-windows-demo --command-id RunPowerShellScript --scripts "@${tmp}/uc2-break.ps1"
    echo "Print Spooler crash loop started (killed every 30s) - '1229 Windows Server Basis - Print Spooler service crashed' should fire in ~1-2 min."
    ;;
  uc2-fix)
    cat > "${tmp}/uc2-fix.ps1" <<'PS'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*demo-uc2-kill-loop.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Remove-Item -Path C:\demo-uc2-kill-loop.ps1 -ErrorAction SilentlyContinue
PS
    az vm run-command invoke -g "${rg}" -n vm-windows-demo --command-id RunPowerShellScript --scripts "@${tmp}/uc2-fix.ps1"
    echo "Crash loop stopped. The alert clears once no new errors appear within its lookback window (~2 min)."
    ;;
  uc3-break)
    flagd_slowdown 5sec
    echo "flagd intlShippingSlowdown -> 5sec - '4720 OTel Astronomy Shop Demo - p95 latency high' should fire in ~1-2 min."
    ;;
  uc3-fix)
    flagd_slowdown off
    echo "flagd intlShippingSlowdown -> off. The alert clears on its next evaluation."
    ;;
  uc4-break)
    kubectl -n observability port-forward svc/loki-gateway 3100:80 >/dev/null 2>&1 &
    pf=$!
    trap 'kill ${pf} 2>/dev/null || true' EXIT
    sleep 3
    echo "Flooding 4711-prod's Loki ingestion for ~2.5 minutes to push it over its daily budget..."
    python3 scripts/demo-uc4-flood.py
    echo "Flood complete. The budget enforcer checks every 2 minutes - allow up to ~2 more minutes for 'Tenant ingestion budget exhausted' to fire for 4711-prod."
    ;;
  uc4-fix)
    cat > "${tmp}/uc4-fix-job.yaml" <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  generateName: demo-uc4-fix-
  namespace: observability
spec:
  backoffLimit: 0
  template:
    metadata:
      annotations:
        linkerd.io/inject: disabled
    spec:
      restartPolicy: Never
      serviceAccountName: ingestion-budget-enforcer
      containers:
        - name: reset
          image: python:3.15.2-slim
          command: ["python3", "/scripts/snapshot.py", "--reset-tenant", "4711-prod"]
          volumeMounts:
            - name: script
              mountPath: /scripts
            - name: budgets
              mountPath: /budgets
      volumes:
        - name: script
          configMap:
            name: ingestion-midnight-snapshot-script
        - name: budgets
          configMap:
            name: tenant-ingestion-budgets
YAML
    job="$(kubectl create -f "${tmp}/uc4-fix-job.yaml" -o jsonpath='{.metadata.name}')"
    kubectl -n observability wait --for=condition=complete "job/${job}" --timeout=60s
    kubectl -n observability logs "job/${job}"
    kubectl -n observability delete job "${job}"
    echo "4711-prod un-throttled and its daily usage reset to 0% for today. The alert clears on its next evaluation."
    ;;
  *)
    echo "Unknown scenario: ${scenario}" >&2
    exit 1
    ;;
esac
