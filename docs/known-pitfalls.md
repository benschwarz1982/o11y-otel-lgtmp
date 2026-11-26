# Known Pitfalls

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
  `az aks update -g <resource-group> -n aks-otel-demo --yes` reconciles
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
  [Processes](self-service.md#processes)); the `destroy:*` bot-author exclusions were
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
  of [Processes](self-service.md#processes)'s manual GitLab setup.
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

- **`grafana.sre.example.com` can serve Traefik's own default self-signed
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
  runtime tenants" under [Multi-Tenancy](setup.md#b9-multi-tenancy-onboarding), but
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
  ([B2](setup.md#b2-lgtmp-stack--otel-collectors)) - independent of
  cert-manager being used for Grafana in
  [B3](setup.md#b3-install-traefik--cert-manager)-[B5](setup.md#b5-grafana-ingress--datasources).
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
  [`helm/values/grafana-values.yaml`](../helm/values/grafana-values.yaml),
  used in [B5](setup.md#b5-grafana-ingress--datasources), sets this
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
  ([A3](setup.md#a3-create-the-gitlab-ci-service-principal),
  [A6](setup.md#a6-create-the-cert-manager-service-principal)) are deliberately
  created via a direct, documented `az` command instead of declarative
  `azuread_*` Terraform resources or a Terraform wrapper around them
  (which would only wrap the same command via `local-exec` anyway).
  Empirically confirmed: even `az ad sp create-for-rbac` itself fails
  with `Insufficient privileges to complete the operation` when run under
  the identity of a **service principal** instead of a human, delegated
  user login (tested with the CI service principal, which has Azure RBAC
  Contributor on the Resource Group) - Azure RBAC roles don't grant Azure
  AD Graph permissions. The
  [A6](setup.md#a6-create-the-cert-manager-service-principal) step therefore
  can't be moved into the pipeline as long as it runs under a pure
  service-principal identity instead of a delegated user session - stays
  permanently manual.
- **DNS zone deliberately kept out of Terraform**: originally the DNS
  zone was part of `modules/networking` and got destroyed along with
  every `destroy:infra` - forcing a fresh, slow Cloudflare NS
  delegation (minutes to ~1h propagation) on every rebuild, just to end
  up with the same subdomain again. The zone is now created manually,
  once ([A2](setup.md#a2-create-dns-zone--cloudflare-ns-delegation)), and only
  referenced from `modules/networking` via `data "azurerm_dns_zone"` - as
  a side effect, this also lets
  [A6](setup.md#a6-create-the-cert-manager-service-principal) (cert-manager SP,
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
  (see [Multi-Tenancy (Onboarding)](setup.md#b9-multi-tenancy-onboarding)) were
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
  fully independent) - see [Destroy](operations.md#destroy) for why forcing that
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
  [A3](setup.md#a3-create-the-gitlab-ci-service-principal)) can manage resources
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
  [A5](setup.md#a5-create-aks-vnet--grant-ci-sp-role-assignment)) - now this
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
  "unverified" gap (see [B10](setup.md#b10-telemetry-schema)), closed out once
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
