variable "resource_group_name" {
  type    = string
  default = "rg-bensc-001"
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the already-existing AKS cluster (created by terraform/environments/demo)"
  default     = "aks-otel-demo"
}

variable "instrument" {
  type        = bool
  default     = false
  description = "false = provision with no telemetry (Demo Runbook step 2, fleet-1294-netzwerk-basis job); true = add OTel instrumentation (Demo Runbook step 4, instrumentation-1294-netzwerk-basis job). Same two-step choreography as every other system in this repo, now a Terraform variable instead of a wholesale ConfigMap swap."
}
