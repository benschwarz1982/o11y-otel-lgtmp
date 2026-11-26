#!/usr/bin/env bash
# Build the job matrices for the deploy/destroy workflows from the
# `systems` input ("all" or comma-separated system IDs, e.g. "1286,4711").
# Writes JSON arrays of {system, image} to $GITHUB_OUTPUT:
#   platform - base tier (needs only the observability stack)
#   apps     - application tier on a base VM (4711 on 1286, 4722 on 1229)
# The image is the CI image (ci/images/Dockerfile target) the job needs
# for the given action.
#
#   ci/scripts/select-systems.sh <provision|instrument|destroy> <systems>
set -euo pipefail

action="${1:?usage: select-systems.sh <provision|instrument|destroy> <systems>}"
selection="${2:-all}"

image_for() { # <system>
  case "${action}:$1" in
    instrument:1286-*|*:4711-*) echo ansible-linux ;;
    instrument:1229-*|*:4722-*) echo ansible-windows ;;
    *) echo terraform ;;
  esac
}

selected() { # <system>
  [ "${selection}" = all ] && return 0
  local id
  IFS=',' read -ra ids <<< "${selection// /}"
  for id in "${ids[@]}"; do
    [ "${1%%-*}" = "${id%%-*}" ] && return 0
  done
  return 1
}

to_json() { # <system>...
  local s first=1
  printf '['
  for s in "$@"; do
    selected "${s}" || continue
    [ "${first}" = 1 ] || printf ','
    first=0
    printf '{"system":"%s","image":"%s"}' "${s}" "$(image_for "${s}")"
  done
  printf ']'
}

platform=(1229-windows-basis 1286-linux-basis 1294-netzwerk-basis 4015-filestorage 4720-otel-astronomy-shop 4721-kundenverwaltung)
apps=(4711-mitarbeiterverzeichnis 4722-spesenabrechnung)

# Reject unknown IDs instead of silently running nothing.
if [ "${selection}" != all ]; then
  IFS=',' read -ra wanted <<< "${selection// /}"
  for id in "${wanted[@]}"; do
    case "${action}:${id%%-*}" in
      destroy:4711|destroy:4722)
        echo "::error::${id} runs on a fleet VM (4711 on 1286, 4722 on 1229) and is destroyed with it - select that system instead." >&2
        exit 1 ;;
    esac
    known=0
    for s in "${platform[@]}" "${apps[@]}"; do
      [ "${s%%-*}" = "${id%%-*}" ] && known=1
    done
    [ "${known}" = 1 ] || { echo "::error::Unknown system: ${id}" >&2; exit 1; }
  done
fi

# 4711/4722 live on the 1286/1229 VMs and are destroyed with them.
[ "${action}" = destroy ] && apps=()

{
  echo "platform=$(to_json "${platform[@]}")"
  echo "apps=$(to_json "${apps[@]}")"
} | tee -a "${GITHUB_OUTPUT:-/dev/null}"
