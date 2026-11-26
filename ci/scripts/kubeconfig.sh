#!/usr/bin/env bash
# Fetch AKS credentials with the az session azure/login opened (OIDC).
set -euo pipefail
az aks get-credentials -g "${AZURE_RESOURCE_GROUP:?}" -n "${AKS_CLUSTER_NAME:?}" --overwrite-existing --only-show-errors
kubectl config current-context
kubectl get nodes
