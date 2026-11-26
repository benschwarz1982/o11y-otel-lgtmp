# Self-Service: Onboarding, Update, Offboarding

## Processes

How systems get onboarded, updated, and offboarded on this platform -
self-service, without ever needing access to this repo.

Sizing drives both onboarding and update requests: environment
retention (Eng: 10 days, AT/Prod: 30 days) × size class (S: 1 GB/day,
M: 10 GB/day, L: 25 GB/day) gives each tenant's storage/daily-ingestion
budget. `scripts/provision.py`'s `compute_overrides()` applies this
automatically for every tenant on every manifest merge (see below,
[B9](setup.md#b9-multi-tenancy-onboarding)) - no by-hand step in the actual
flow. `python3 scripts/calculate-ingestion-budget.py --app <appname>
--env <eng|at|prod> --size <S|M|L>` predates the rate-limit/daily-budget
decoupling ([B9](setup.md#b9-multi-tenancy-onboarding)) and still derives its
printed rate-limit YAML from size the old way - only its storage-budget
math still matches `compute_overrides()`; not updated since it's no
longer on the real path.

Two ways to submit any request: the **self-service form**
([`form/index.html`](../form/index.html), published via GitLab Pages -
the `pages` job in [`.gitlab-ci.yml`](../.gitlab-ci.yml), runs on every
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

And the same **provisioning + rollout**. [`scripts/provision.py`](../scripts/provision.py)
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
[Multi-Tenancy](setup.md#b9-multi-tenancy-onboarding)). **Every** tenant is
included, 4087 (the platform itself) as well - no special-casing.

These generated files are part of the **merge request itself**: the
three `tenants:*-mr` jobs apply the manifest change to their checkout,
run `provision.py`, and commit the manifest and every generated change
in one commit ([`scripts/provisioning_sync.py`](../scripts/provisioning_sync.py)),
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
curl -X POST "https://gitlab.com/api/v4/projects/<project-id>/pipeline" \
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
[`manifests/schema.json`](../manifests/schema.json) for the full field
reference.

The `tenants:create-mr` job (see
[`scripts/create-onboarding-mr.py`](../scripts/create-onboarding-mr.py))
turns the submitted fields into a manifest, validates it against [the
schema](../manifests/schema.json), and opens an MR - one new file under
`manifests/platforms/` or `manifests/applications/`, nothing else
touched.

### Update

**Via the form**: switch to "Update an existing system" mode - only
System ID, Owner, and Environments & Ingestion Budget are
shown/editable, System ID/type/name aren't. For example, resizing
4087's `prod` budget from `L` to `M`.

**Via the API** - the same 4087 resize as an example:

```bash
curl -X POST "https://gitlab.com/api/v4/projects/<project-id>/pipeline" \
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
[`scripts/create-update-mr.py`](../scripts/create-update-mr.py)) - gated
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
curl -X POST "https://gitlab.com/api/v4/projects/<project-id>/pipeline" \
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
[`scripts/create-offboarding-mr.py`](../scripts/create-offboarding-mr.py)) -
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
