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

: "${TFSTATE_RESOURCE_GROUP:?set TFSTATE_RESOURCE_GROUP (from bootstrap.sh)}" "${TFSTATE_STORAGE_ACCOUNT:?set TFSTATE_STORAGE_ACCOUNT (from bootstrap.sh)}" "${TFSTATE_CONTAINER:?set TFSTATE_CONTAINER (from bootstrap.sh)}"
# An unset repository variable arrives as "" - which Terraform accepts as
# a value for a required variable. Fail here with a clear message instead.
: "${TF_VAR_resource_group_name:?set AZURE_RESOURCE_GROUP (repository variable or demo environment secret)}"
: "${TF_VAR_dns_zone_name:?set DNS_ZONE (repository variable or demo environment secret)}"

terraform -chdir="${dir}" init -input=false -no-color \
  -backend-config="resource_group_name=${TFSTATE_RESOURCE_GROUP}" \
  -backend-config="storage_account_name=${TFSTATE_STORAGE_ACCOUNT}" \
  -backend-config="container_name=${TFSTATE_CONTAINER}" \
  -backend-config="key=${env_name}.tfstate"
