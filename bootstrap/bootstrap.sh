#!/usr/bin/env bash
# One-time Azure bootstrap for the GitHub Actions pipeline. Run in Azure
# Cloud Shell (Bash) as Owner of the resource group:
#
#   GITHUB_REPO=<owner>/<repo> ./bootstrap.sh
#
# Creates (idempotent, safe to re-run):
#   - a storage account for the Terraform state (Entra ID auth only - no
#     shared keys -, versioning + 30 days soft delete), container "tfstate"
#   - user-assigned managed identity id-otel-demo-deploy with GitHub OIDC
#     federated credentials for the GitHub environment "demo" (no client
#     secret anywhere)
#   - its role assignments:
#       Contributor                          on the resource group
#       Storage Blob Data Contributor        on the state storage account
#       Role Based Access Control Administrator on aks-vnet, restricted by
#         an ABAC condition to granting/removing "Network Contributor"
#         (the AKS identity needs it on the VNet - terraform/modules/aks-cluster)
# and prints the GitHub repository variables to set.
#
# Prerequisites from README section A (unchanged): resource group, DNS
# zone, aks-vnet/aks-subnet, cert-manager service principal.
#
# OIDC subject: GitHub repositories created since 2026 put immutable IDs
# into the token subject (repo:<owner>@<owner-id>/<repo>@<repo-id>:...),
# older ones use repo:<owner>/<repo>:... - both are registered. If a run
# still fails with AADSTS700213 "No matching federated identity record",
# re-run with OIDC_SUBJECT_PREFIX=<everything before ":environment:" in
# that error message>.
set -euo pipefail

: "${GITHUB_REPO:?Set GITHUB_REPO=<owner>/<repo>}"
RG="${RG:-rg-bensc-001}"
VNET="${VNET:-aks-vnet}"
ENVIRONMENT="${ENVIRONMENT:-demo}"
CONTAINER="${CONTAINER:-tfstate}"
IDENTITY="${IDENTITY:-id-otel-demo-deploy}"
NETWORK_CONTRIBUTOR=4d97b98b-1d4f-4787-a291-c67834d212e7
RBAC_ADMIN="Role Based Access Control Administrator"

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
LOCATION="$(az group show -n "$RG" --query location -o tsv)"
echo "Subscription $(az account show --query name -o tsv), resource group $RG ($LOCATION)"

# Storage account names: 3-24 lowercase alphanumerics, globally unique ->
# stable suffix derived from subscription + resource group.
SA="${SA:-stotelstate$(echo -n "$SUB_ID/$RG" | sha256sum | cut -c1-10)}"

echo "State storage account $SA"
az storage account create -g "$RG" -n "$SA" -l "$LOCATION" \
  --sku Standard_ZRS --kind StorageV2 \
  --min-tls-version TLS1_2 --https-only true \
  --allow-blob-public-access false \
  --allow-shared-key-access false \
  -o none
az storage account blob-service-properties update -g "$RG" --account-name "$SA" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 30 \
  --enable-container-delete-retention true --container-delete-retention-days 30 \
  -o none
SA_ID="$(az storage account show -g "$RG" -n "$SA" --query id -o tsv)"

# Data-plane access for the person running this, to create the container
ME="$(az ad signed-in-user show --query id -o tsv)"
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none 2>/dev/null || true
echo "Creating container $CONTAINER (waits for the role assignment to propagate)"
for _ in $(seq 1 18); do
  az storage container create --account-name "$SA" -n "$CONTAINER" --auth-mode login -o none 2>/dev/null && break
  sleep 10
done
az storage container show --account-name "$SA" -n "$CONTAINER" --auth-mode login -o none

echo "Managed identity $IDENTITY"
az identity create -g "$RG" -n "$IDENTITY" -l "$LOCATION" -o none
CLIENT_ID="$(az identity show -g "$RG" -n "$IDENTITY" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show -g "$RG" -n "$IDENTITY" --query principalId -o tsv)"

federate() { # credential-name subject
  az identity federated-credential create -g "$RG" --identity-name "$IDENTITY" -n "$1" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "$2" --audiences "api://AzureADTokenExchange" -o none 2>/dev/null \
  || az identity federated-credential update -g "$RG" --identity-name "$IDENTITY" -n "$1" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "$2" --audiences "api://AzureADTokenExchange" -o none
  echo "  federated: $2"
}
if [ -n "${OIDC_SUBJECT_PREFIX:-}" ]; then
  federate "github-env-${ENVIRONMENT}" "${OIDC_SUBJECT_PREFIX}:environment:${ENVIRONMENT}"
else
  federate "github-env-${ENVIRONMENT}" "repo:${GITHUB_REPO}:environment:${ENVIRONMENT}"
  # Immutable-ID subject (public repository: no token needed for the lookup)
  ids="$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r["owner"]["login"], r["owner"]["id"], r["name"], r["id"])')" \
    || { echo "Could not read the repository from the GitHub API - is it public and spelled correctly?" >&2; exit 1; }
  read -r owner owner_id repo repo_id <<< "$ids"
  federate "github-env-${ENVIRONMENT}-ids" "repo:${owner}@${owner_id}/${repo}@${repo_id}:environment:${ENVIRONMENT}"
fi

assign() { # role scope [condition]
  local args=(--assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "$1" --scope "$2" -o none)
  [ -n "${3:-}" ] && args+=(--condition "$3" --condition-version 2.0)
  # A fresh identity can take a moment to show up in Entra ID
  for _ in $(seq 1 12); do
    az role assignment create "${args[@]}" 2>/dev/null && { echo "  role: $1"; return 0; }
    sleep 10
  done
  az role assignment create "${args[@]}"
}
RG_ID="$(az group show -n "$RG" --query id -o tsv)"
VNET_ID="$(az network vnet show -g "$RG" -n "$VNET" --query id -o tsv)"
# Constrained delegation: may only grant/remove Network Contributor.
CONDITION="((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${NETWORK_CONTRIBUTOR}})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${NETWORK_CONTRIBUTOR}}))"

echo "Role assignments for $IDENTITY"
assign "Contributor" "$RG_ID"
assign "Storage Blob Data Contributor" "$SA_ID"
assign "$RBAC_ADMIN" "$VNET_ID" "$CONDITION"

cat <<EOF

Done. GitHub -> Settings -> Secrets and variables -> Actions -> Variables:

  AZURE_TENANT_ID          $TENANT_ID
  AZURE_SUBSCRIPTION_ID    $SUB_ID
  AZURE_CLIENT_ID          $CLIENT_ID
  TFSTATE_RESOURCE_GROUP   $RG
  TFSTATE_STORAGE_ACCOUNT  $SA
  TFSTATE_CONTAINER        $CONTAINER

Then create the environment "$ENVIRONMENT" (deployment branches: main only)
and put the secrets there - see README "GitHub Actions".
EOF
