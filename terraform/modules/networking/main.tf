# AKS VNet - NOT created by Terraform (only referenced), same decoupling
# reason as the DNS zone below: the CI Service Principal needs "User
# Access Administrator" scoped to this exact VNet before Terraform's own
# azurerm_role_assignment.aks_identity_network_contributor
# (terraform/modules/aks-cluster/main.tf) can succeed - and that grant
# does NOT survive the VNet being deleted and recreated (even though its
# resource ID is deterministic by name, Azure does not preserve role
# assignments scoped to a resource across that resource's own
# delete+recreate). Making the VNet itself a one-time manual bootstrap
# resource (main README section A5) makes the grant genuinely one-time
# too, instead of a manual step required after every destroy:infra +
# deploy:infra cycle.
data "azurerm_virtual_network" "aks" {
  name                = "aks-vnet"
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.aks.name
}

# Neutral VNet for VM-based clients (Linux/Windows), see README
# "VNet peering & internal gateway". ClusterIP services are not reachable
# from outside the AKS VNet, hence peering + an internal LoadBalancer are needed.
resource "azurerm_virtual_network" "clients" {
  name                = "observability-clients-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.clients_vnet_address_space
}

resource "azurerm_subnet" "clients" {
  name                 = "clients-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.clients.name
  address_prefixes     = var.clients_subnet_address_prefix
}

resource "azurerm_virtual_network_peering" "aks_to_clients" {
  name                         = "aks-to-clients"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = data.azurerm_virtual_network.aks.name
  remote_virtual_network_id    = azurerm_virtual_network.clients.id
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "clients_to_aks" {
  name                         = "clients-to-aks"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.clients.name
  remote_virtual_network_id    = data.azurerm_virtual_network.aks.id
  allow_virtual_network_access = true
}

# The DNS zone is NOT created by Terraform (only referenced) - its lifecycle
# is deliberately decoupled from the AKS cluster/VNet destroy cycle,
# otherwise every terraform destroy/apply cycle would require a fresh, slow
# NS delegation at the main DNS provider (see main README section A2). The
# zone is created manually, once.
data "azurerm_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = var.resource_group_name
}
