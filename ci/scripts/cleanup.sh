#!/bin/sh
# Last step of every self-hosted job. The jobs run as root inside the CI
# image container on a persistent VM: remove the sensitive files they
# leave behind - SSH/WinRM key material, the generated Ansible inventory
# (Windows admin password), kubeconfigs Terraform writes - so nothing
# sensitive stays on disk.
#
# Deliberately NOT a full workspace wipe: post-job steps (azure/login's
# logout) are loaded again from .github/actions/ in the workspace after
# this step; the next job's checkout cleans the rest.
set -u
[ -n "${RUNNER_TEMP:-}" ] && rm -rf "${RUNNER_TEMP}/otel-demo"
if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -d "${GITHUB_WORKSPACE}" ]; then
  rm -f "${GITHUB_WORKSPACE}/ansible/inventory/generated.ini"
  rm -f "${GITHUB_WORKSPACE}"/terraform/environments/*/.terraform-kubeconfig
  rm -rf "${GITHUB_WORKSPACE}"/terraform/environments/*/.terraform
fi
rm -rf "${HOME:-/root}/.kube"
exit 0
