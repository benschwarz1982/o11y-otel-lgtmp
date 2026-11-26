#!/usr/bin/env bash
# Installs GitHub Actions self-hosted runners (label "otel-demo") on the
# management VM, next to the GitLab runner. Deploy jobs need this VM:
# the fleet VMs only accept SSH/WinRM from its public IP
# (mgmt-gitlab-runner-pip, see terraform/environments/fleet-*).
#
# Run on the VM as a sudo-capable user:
#
#   GITHUB_REPO=<owner>/<repo> RUNNER_TOKEN=<token> RUNNER_COUNT=2 ./github-runner.sh
#
# RUNNER_TOKEN: Settings -> Actions -> Runners -> New self-hosted runner
# (valid for one hour). Each runner runs one job at a time; RUNNER_COUNT
# runners let independent jobs (e.g. the fleet matrix) run in parallel -
# mind the VM's memory. Jobs run in containers (Docker), as a dedicated
# non-login user in the docker group.
#
# Public repository: only workflows started by maintainers
# (workflow_dispatch, push to main, issues from collaborators) use these
# runners - nothing triggered by pull requests does. Also set
# Settings -> Actions -> General -> "Require approval for all external
# contributors".
set -euo pipefail

: "${GITHUB_REPO:?Set GITHUB_REPO=<owner>/<repo>}"
: "${RUNNER_TOKEN:?Set RUNNER_TOKEN (Settings -> Actions -> Runners -> New self-hosted runner)}"
RUNNER_COUNT="${RUNNER_COUNT:-2}"
RUNNER_VERSION="${RUNNER_VERSION:-2.338.2}"
RUNNER_USER="${RUNNER_USER:-ghrunner}"
LABELS="${LABELS:-otel-demo}"

command -v docker >/dev/null || { echo "Docker is required (already installed for the GitLab runner)." >&2; exit 1; }

if ! id "$RUNNER_USER" >/dev/null 2>&1; then
  sudo useradd --system --create-home --shell /usr/sbin/nologin "$RUNNER_USER"
fi
sudo usermod -aG docker "$RUNNER_USER"

tarball="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${tarball}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/$tarball" "$url"
# The release notes publish the SHA-256 of every package; check it.
expected="$(curl -fsSL "https://api.github.com/repos/actions/runner/releases/tags/v${RUNNER_VERSION}" \
  | python3 -c 'import json,re,sys; body=json.load(sys.stdin)["body"]; m=re.search(r"<!-- BEGIN SHA linux-x64 -->([0-9a-f]{64})", body); print(m.group(1) if m else "")')"
[ -n "$expected" ] || { echo "Could not find the published checksum for $tarball" >&2; exit 1; }
echo "$expected  $tmp/$tarball" | sha256sum -c -

for i in $(seq 1 "$RUNNER_COUNT"); do
  dir="/opt/actions-runner-$i"
  name="$(hostname)-$i"
  if [ -f "$dir/.runner" ]; then
    echo "$name already configured, skipping"
    continue
  fi
  sudo mkdir -p "$dir"
  sudo tar -xzf "$tmp/$tarball" -C "$dir"
  sudo chown -R "$RUNNER_USER:$RUNNER_USER" "$dir"
  sudo "$dir/bin/installdependencies.sh" >/dev/null
  sudo -u "$RUNNER_USER" "$dir/config.sh" --unattended \
    --url "https://github.com/${GITHUB_REPO}" --token "$RUNNER_TOKEN" \
    --name "$name" --labels "$LABELS" --work _work --replace
  (cd "$dir" && sudo ./svc.sh install "$RUNNER_USER" && sudo ./svc.sh start)
done
echo "Runners registered - check Settings -> Actions -> Runners."
