variable "resource_group_name" {
  type = string
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the already-existing AKS cluster (created by terraform/environments/demo)"
  default     = "aks-otel-demo"
}

variable "openclaw_gateway_token" {
  type        = string
  description = "Shared secret between Grafana's webhook contact point (alerting/shared/openclaw-webhook.yaml) and OpenClaw's own gateway auth (terraform/environments/observability-stack). Must be set to the same value in both Terraform states' CI/CD variables."
  default     = ""
  sensitive   = true
}
