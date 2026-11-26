#!/usr/bin/env bash
# terraform init for one environment against the Azure Storage state
# backend (created by bootstrap/bootstrap.sh). Auth: Entra ID via GitHub
# OIDC (ARM_USE_OIDC/ARM_USE_AZUREAD/ARM_CLIENT_ID set by the workflow).
#
#   ci/scripts/tf-init.sh <environment>     # e.g. observability-stack
set -euo pipefail

env_name="${1:?usage: tf-init.sh <environment>}"
dir="terraform/environments/${env_name}"
[ -d "${dir}" ] || { echo "No such environment: ${dir}" >&2; exit 1; }

: "${TFSTATE_RESOURCE_GROUP:?}" "${TFSTATE_STORAGE_ACCOUNT:?}" "${TFSTATE_CONTAINER:?}"

terraform -chdir="${dir}" init -input=false -no-color \
  -backend-config="resource_group_name=${TFSTATE_RESOURCE_GROUP}" \
  -backend-config="storage_account_name=${TFSTATE_STORAGE_ACCOUNT}" \
  -backend-config="container_name=${TFSTATE_CONTAINER}" \
  -backend-config="key=${env_name}.tfstate"
