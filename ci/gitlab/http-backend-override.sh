#!/bin/sh
# The Terraform code declares an azurerm backend (GitHub Actions, see
# ci/scripts/tf-init.sh). The GitLab pipeline keeps using GitLab's own
# HTTP state backend: this writes an override file into the given
# environment directory before `terraform init` (override files are
# git-ignored).
set -eu
dir="${1:?usage: http-backend-override.sh <terraform-environment-dir>}"
printf 'terraform {\n  backend "http" {}\n}\n' > "${dir}/backend_override.tf"
