# Runbook: shared-ingestion-budget-missing (Diagnosis only)

This runbook is used when an alert with
`Runbook-Key: shared-ingestion-budget-missing` fires (`Ingestion budget
not enforced for a tenant`). The alert message names either a tenant
(`<system_id>-<env>`, e.g. `1294-prod`) or `all`.

Background: daily ingestion budgets come from
`helm/values/ingestion-daily-budgets.yaml` (generated from each tenant's
manifest by `scripts/provision.py`), are rolled out by the
`tenants:rollout` CI job as the `tenant-ingestion-budgets` ConfigMap in
the `observability` namespace, and are enforced every 2 minutes by the
`ingestion-midnight-snapshot` CronJob there. Each run pushes per-tenant
usage (`demo_ingestion_since_midnight`) and budgets
(`demo_ingestion_daily_budget`) as metrics; the alert is computed from
those metrics.

⚠️ Diagnosis only. You have no access to the Kubernetes cluster or the
CI pipeline, and this is not a problem on the demo VM - do NOT run any
command, over SSH or otherwise, for this alert. Your reply is the
deliverable.

## Steps for the Agent

1. **Decide which case it is** from the name in the alert message.

2. **Case A - a tenant (e.g. `1294-prod`):** that tenant ingests data on
   at least one signal (metrics, logs, traces, profiles) without a
   positive daily budget, so nothing would throttle it once it exceeds
   its tier. Explain this in two or three sentences, then propose these
   checks to the operator as a numbered list, with the tenant filled in
   for `<TENANT>`:

   1. Is the tenant, with all four signals, in the budgets ConfigMap?
      ```bash
      kubectl get configmap tenant-ingestion-budgets -n observability \
        -o jsonpath='{.data.ingestion-daily-budgets\.yaml}' | grep -A4 '<TENANT>:'
      ```
   2. Is it in `helm/values/ingestion-daily-budgets.yaml` on `main`? If
      yes but missing or incomplete in the ConfigMap: run
      `tenants:rollout` (Run pipeline on `main`). If missing in the file
      too: the tenant's manifest and the generated files disagree -
      `provision:check` / `tenants:apply` in the last pipeline list the
      affected files.
   3. Then check the enforcer as in Case B, step 1 - the alert only
      clears once a run has pushed the restored budget.

3. **Case B - `all`:** no usage metrics from the enforcer have arrived
   for 15 minutes, so it is unknown whether ANY tenant's budget is
   currently enforced. Possible causes: the CronJob is not running or
   failing, its usage queries returned nothing, its metric push failed,
   or the budgets ConfigMap is missing. Do not claim one cause. Propose:

   1. Latest CronJob runs and the log of the newest one:
      ```bash
      kubectl get jobs -n observability --sort-by=.metadata.creationTimestamp | grep ingestion-midnight-snapshot | tail -3
      kubectl logs -n observability job/<newest-job-name>
      ```
      Look for `ERROR`/`WARNING` lines: a `... not found - tenant budgets
      are not provisioned` warning means the ConfigMap is missing (run
      `tenants:rollout`); query or push errors point at Mimir.
   2. Does the ConfigMap exist at all?
      ```bash
      kubectl get configmap tenant-ingestion-budgets -n observability
      ```
   3. Is the CronJob suspended or failing to schedule?
      ```bash
      kubectl get cronjob ingestion-midnight-snapshot -n observability
      ```

4. **Completion:** State clearly that you did not change anything and
   cannot verify recovery yourself. The alert clears only after a later
   enforcer run has read a positive budget and pushed its metrics
   successfully - ask the operator to confirm it has cleared.
