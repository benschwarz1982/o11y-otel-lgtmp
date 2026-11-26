# The Resource Group is NOT created by Terraform (only referenced) - in
# sandbox/playground subscriptions it is usually pre-provisioned and "az group
# create" is not allowed, see README "Note on sandbox environments".
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

module "networking" {
  source = "../../modules/networking"

  resource_group_name           = data.azurerm_resource_group.main.name
  location                      = data.azurerm_resource_group.main.location
  dns_zone_name                 = var.dns_zone_name
  clients_vnet_address_space    = var.clients_vnet_address_space
  clients_subnet_address_prefix = var.clients_subnet_address_prefix
}

module "aks" {
  source = "../../modules/aks-cluster"

  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  cluster_name        = var.aks_cluster_name
  node_count          = var.aks_node_count
  node_vm_size        = var.aks_node_vm_size
  vnet_subnet_id      = module.networking.aks_subnet_id
  vnet_id             = module.networking.aks_vnet_id
}
