output "aks_vnet_id" {
  value = data.azurerm_virtual_network.aks.id
}

output "aks_vnet_name" {
  value = data.azurerm_virtual_network.aks.name
}

output "aks_subnet_id" {
  value = data.azurerm_subnet.aks.id
}

output "clients_vnet_id" {
  value = azurerm_virtual_network.clients.id
}

output "clients_vnet_name" {
  value = azurerm_virtual_network.clients.name
}

output "clients_subnet_id" {
  value = azurerm_subnet.clients.id
}

output "clients_subnet_name" {
  value = azurerm_subnet.clients.name
}

output "dns_zone_id" {
  value = data.azurerm_dns_zone.main.id
}

output "dns_zone_name" {
  value = data.azurerm_dns_zone.main.name
}

output "dns_zone_nameservers" {
  value = data.azurerm_dns_zone.main.name_servers
}
