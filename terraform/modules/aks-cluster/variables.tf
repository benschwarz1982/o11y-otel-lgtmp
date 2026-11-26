variable "resource_group_name" {
  type        = string
  description = "Name of the Resource Group"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "cluster_name" {
  type        = string
  description = "Name of the AKS cluster"
}

variable "node_count" {
  type        = number
  description = "Number of nodes in the default node pool"
}

variable "node_vm_size" {
  type        = string
  description = "VM size of the nodes"
}

variable "vnet_subnet_id" {
  type        = string
  description = "Subnet ID in which the AKS nodes run (from the networking module)"
}

variable "vnet_id" {
  type        = string
  description = "aks-vnet's own resource ID (from the networking module) - the cluster identity's Network Contributor role assignment is scoped to this, not just the subnet, matching how it was granted manually before this was automated"
}
