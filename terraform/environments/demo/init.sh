#!/usr/bin/env bash
# Initializes Terraform against the GitLab-managed state backend.
#
# Local usage (e.g. Azure Cloud Shell) - requires a GitLab personal
# access token with "api" scope (https://gitlab.com/-/user_settings/personal_access_tokens):
#   export GITLAB_USERNAME=<your-gitlab-username>
#   export GITLAB_TOKEN=<your-personal-access-token>
#   export TF_PROJECT_ID=<gitlab-project-id>   # project overview page or Settings > General
#   ./init.sh
#
# In the GitLab CI pipeline, $CI_JOB_TOKEN is used instead (rather than a
# personal access token) - see .gitlab-ci.yml.
set -euo pipefail

: "${TF_PROJECT_ID:?TF_PROJECT_ID must be set (GitLab project ID)}"
: "${GITLAB_USERNAME:?GITLAB_USERNAME must be set}"
: "${GITLAB_TOKEN:?GITLAB_TOKEN must be set (personal access token with 'api' scope)}"

# The code declares an azurerm backend (GitHub Actions); GitLab state needs
# the HTTP backend override, same as the GitLab pipeline.
"$(dirname "$0")/../../../ci/gitlab/http-backend-override.sh" "$(dirname "$0")"

TF_STATE_NAME="${TF_STATE_NAME:-demo}"
TF_ADDRESS="https://gitlab.com/api/v4/projects/${TF_PROJECT_ID}/terraform/state/${TF_STATE_NAME}"

terraform init \
  -backend-config="address=${TF_ADDRESS}" \
  -backend-config="lock_address=${TF_ADDRESS}/lock" \
  -backend-config="unlock_address=${TF_ADDRESS}/lock" \
  -backend-config="username=${GITLAB_USERNAME}" \
  -backend-config="password=${GITLAB_TOKEN}" \
  -backend-config="lock_method=POST" \
  -backend-config="unlock_method=DELETE" \
  -backend-config="retry_wait_min=5"
