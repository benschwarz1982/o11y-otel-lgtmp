variable "resource_group_name" {
  type = string
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the already-existing AKS cluster (created by terraform/environments/demo)"
  default     = "aks-otel-demo"
}

variable "dns_zone_name" {
  type        = string
  description = "Name of the already existing Azure DNS subdomain zone (see main README section A2)"
}

variable "instrument" {
  type        = bool
  default     = false
  description = "false = provision with no telemetry (Demo Runbook step 2, deploy-fleets:4721-kundenverwaltung job - Kundenverwaltung's own OTLP endpoint/tenant header are already baked in either way, only the OTel Java agent attachment is toggled, same as the original app.yaml); true = add OTel instrumentation (Demo Runbook step 4, deploy-instrumentations:4721-kundenverwaltung job - also creates the postgres-otel-collector OpenTelemetryCollector, which never existed before this step)."
}
