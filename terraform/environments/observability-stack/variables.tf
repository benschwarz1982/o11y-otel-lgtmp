variable "resource_group_name" {
  type        = string
  description = "Name of the (already existing) Azure Resource Group, see terraform/environments/demo/variables.tf"
  default     = "rg-bensc-001"
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the already-existing AKS cluster (created by terraform/environments/demo)"
  default     = "aks-otel-demo"
}

variable "dns_zone_name" {
  type        = string
  description = "Name of the already existing Azure DNS subdomain zone (see README section A2)"
  default     = "sre.fs167.ch"
}

variable "cert_manager_client_id" {
  type        = string
  description = "App ID of the cert-manager Service Principal (README section A5). Empty string skips the ClusterIssuer/azuredns-config secret entirely, same as CERT_MANAGER_CLIENT_ID being unset today."
  default     = ""
}

variable "cert_manager_client_secret" {
  type        = string
  description = "Secret of the cert-manager Service Principal (README section A5)."
  default     = ""
  sensitive   = true
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana admin password (helm_release.grafana). Empty string (the default) lets the chart auto-generate its own random password instead, same as before this variable existed - retrieve it via `kubectl get secret grafana -n observability -o jsonpath='{.data.admin-password}' | base64 -d`."
  default     = ""
  sensitive   = true
}


variable "openclaw_hooks_token" {
  type        = string
  description = "Bearer token Grafana's webhook contact point (alerting/shared/openclaw-webhook.yaml) sends to OpenClaw's /hooks/agent endpoint. Stored in the platform Key Vault (write-only, not in the Terraform state) and mounted into Grafana by the Secrets Store CSI driver, read via $__file{} - never rendered into a ConfigMap or Kubernetes Secret. Required (precondition on azurerm_key_vault_secret.openclaw_hooks_token). Same CI/CD variable (OPENCLAW_HOOKS_TOKEN) as terraform/environments/aiops."
  default     = ""
  sensitive   = true
}
