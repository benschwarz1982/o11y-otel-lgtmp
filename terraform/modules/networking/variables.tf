variable "resource_group_name" {
  type        = string
  description = "Name of the Resource Group in which the network resources are created"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "dns_zone_name" {
  type        = string
  description = "Name of the already existing Azure DNS subdomain zone (e.g. sre.fs167.ch) - referenced via a data source, not created by Terraform (see main README section A2)"
}

variable "clients_vnet_address_space" {
  type        = list(string)
  description = "Address space of the VNet for VM-based clients (Linux/Windows)"
}

variable "clients_subnet_address_prefix" {
  type        = list(string)
  description = "Address space of the client subnet"
}
