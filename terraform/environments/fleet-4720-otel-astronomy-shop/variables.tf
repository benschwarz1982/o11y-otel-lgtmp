variable "resource_group_name" {
  type    = string
  default = "rg-bensc-001"
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the already-existing AKS cluster (created by terraform/environments/demo)"
  default     = "aks-otel-demo"
}

variable "dns_zone_name" {
  type        = string
  description = "Name of the already existing Azure DNS subdomain zone (see main README section A2)"
  default     = "sre.fs167.ch"
}

variable "instrument" {
  type        = bool
  default     = false
  description = "false = provision with no telemetry (Demo Runbook step 2, fleet-4720-otel-astronomy-shop job - base values.yaml only); true = add OTel instrumentation (Demo Runbook step 4, instrumentation-4720-otel-astronomy-shop job - layers values-instrument.yaml's envOverrides on top, replacing the old `helm upgrade --reuse-values` two-step)."
}
