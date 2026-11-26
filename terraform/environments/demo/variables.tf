variable "resource_group_name" {
  type        = string
  description = "Name of the (already existing) Azure Resource Group - usually pre-provisioned in sandbox subscriptions, see README"
  default     = "rg-bensc-001"
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "switzerlandnorth"
}

variable "dns_zone_name" {
  type        = string
  description = "Name of the already existing Azure DNS subdomain zone (created manually, see README section A2)"
  default     = "sre.fs167.ch"
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the AKS cluster"
  default     = "aks-otel-demo"
}

variable "aks_node_count" {
  type        = number
  description = "Number of nodes in the default node pool"
  default     = 7
}

variable "aks_node_vm_size" {
  type        = string
  description = "VM size of the AKS nodes"
  default     = "Standard_D4s_v5"
}

variable "clients_vnet_address_space" {
  type    = list(string)
  default = ["10.1.0.0/16"]
}

variable "clients_subnet_address_prefix" {
  type    = list(string)
  default = ["10.1.1.0/24"]
}
