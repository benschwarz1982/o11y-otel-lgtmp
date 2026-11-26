variable "resource_group_name" {
  type = string
}

variable "location" {
  type    = string
  default = "switzerlandnorth"
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the already-existing AKS cluster (created by terraform/environments/demo)"
  default     = "aks-otel-demo"
}

variable "instrument" {
  type        = bool
  default     = false
  description = "false = provision with an inert OTLP endpoint (Demo Runbook step 2, fleet-4015-filestorage job); true = point at the real gateway (Demo Runbook step 4, instrumentation-4015-filestorage job)."
}
