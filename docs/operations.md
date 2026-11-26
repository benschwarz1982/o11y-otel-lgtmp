# Operations: Scans and Teardown

## Scheduled Scans

`validate:python-deps` (pip-audit on the pinned Python requirements) and
`build:ci-image-scan` (trivy on the 4 ci-tools images) also run on a
pipeline schedule, so newly published vulnerabilities show up without a
change in this repo. One-time setup in the GitLab UI: Build → Pipeline
schedules → New schedule, target branch `main`, e.g. weekly. No other
job runs on a schedule. Dependency versions are bumped by hand.

## Destroy

### Infrastructure & Observability Stack (Pipeline)

**GitHub Actions:** Actions → *Destroy* → Run workflow → scope
`everything`, type `destroy` into the confirm field. The workflow runs the
same order as below (aiops → fleets + tenants → observability stack →
infra).

**GitLab CI:** set the CI/CD variable `CONFIRM_DESTROY=yes`, then start
the manual jobs in the `destroy` stage, in order:

0. **`destroy:aiops`**: removes the OpenClaw remediation agent. Run it
   first - it is not a `needs` of the later jobs, so nothing enforces
   the order, but its resources live on the cluster `destroy:infra`
   deletes.
1. **The six fleet-teardown `destroy:*` jobs** (one per underlying VM/namespace) and
   **`destroy:tenants`**: the fleet-teardown jobs tear down the two demo VMs
   (including their NICs/public IPs/NSGs/OS disks - each VM's job also
   covers whatever's staged on top of it, e.g.
   `destroy:1286-linux-basis` also removes 4711) and the
   Kubernetes-based apps (Astronomy Shop, Kundenverwaltung -
   `destroy:4721-kundenverwaltung` also removes its dedicated
   PostgreSQL database - SNMP simulator, Filestorage - including its
   Storage Account). `destroy:tenants` tears
   down every onboarded tenant's own datasource/dashboard ConfigMaps and
   the gateway `OpenTelemetryCollector` CR. All seven are independent -
   run whichever ones you need, in any order (among themselves).
2. **`destroy:observability-stack`**: tears down the LGTM+P stack + collectors (Helm
   releases, `observability`/`opentelemetry-operator-system` namespaces).
   `needs` all six fleet-teardown `destroy:*` jobs **and** `destroy:tenants`
   (`optional: true`, but since they always exist in the pipeline they
   still gate this job in practice - it won't show as playable until all
   seven have run). `destroy:tenants` specifically must go first, not
   just conveniently before: its gateway CR's `null_resource` shells out
   to `kubectl delete opentelemetrycollector` on destroy, which needs the
   `OpenTelemetryCollector` CRD schema this job's own Helm release
   installs to still be present.
3. **`destroy:infra`** (deliberately last): tears down the AKS cluster
   and network - the DNS zone stays untouched (see
   [A2](setup.md#a2-create-dns-zone--cloudflare-ns-delegation)), no fresh
   Cloudflare NS delegation needed on the next `deploy:infra`. `needs`
   `destroy:observability-stack` the same way.

Afterwards, set `CONFIRM_DESTROY` back to `no`/remove it, to avoid
accidental destruction on future runs.

The observability stack's Key Vault is only **soft-deleted**
(`purge_soft_delete_on_destroy = false`): purging needs a
subscription-level permission the pipeline identities don't have. It
expires after 7 days and doesn't block a rebuild - the next deploy
creates a vault with a new random name.

`az resource list -g <resource-group> -o table` after a full cleanup
(all `destroy:*` jobs run) should show only the DNS zone and `aks-vnet`
(one-time bootstrap resources, see
[A2](setup.md#a2-create-dns-zone--cloudflare-ns-delegation)/[A5](setup.md#a5-create-aks-vnet--grant-ci-sp-role-assignment) -
neither is touched by `destroy:infra`).

### Cleaning Up the DNS Zone + Delegation (Manual)

Only relevant if the DNS zone is no longer needed permanently - in the
normal destroy/deploy cycle it deliberately stays in place (see
[A2](setup.md#a2-create-dns-zone--cloudflare-ns-delegation)):

```bash
az network dns zone delete -g $RESOURCE_GROUP -n sre.example.com
```

At your main DNS provider (e.g. Cloudflare), also delete the 4 NS entries
for the `sre` subdomain that were created in
[A2](setup.md#a2-create-dns-zone--cloudflare-ns-delegation).
