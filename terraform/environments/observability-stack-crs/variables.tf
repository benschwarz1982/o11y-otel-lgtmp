variable "resource_group_name" {
  type        = string
  description = "Name of the (already existing) Azure Resource Group, see terraform/environments/demo/variables.tf"
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the already-existing AKS cluster (created by terraform/environments/demo)"
  default     = "aks-otel-demo"
}

variable "cert_manager_client_id" {
  type        = string
  description = "App ID of the cert-manager Service Principal (README section A5). Empty string skips the ClusterIssuer/Certificate/IngressRoute entirely, same as ../observability-stack skipping the azuredns-config secret - must be passed the same value to both modules."
  default     = ""
}

variable "dns_zone_name" {
  type        = string
  description = "Azure DNS zone of the public hostnames (e.g. sre.example.com) - set via TF_VAR_dns_zone_name"
}

variable "acme_email" {
  type        = string
  default     = ""
  description = "Contact e-mail for the Let's Encrypt account (expiry notices); empty = no contact address"
}
