output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "aks_node_resource_group" {
  value = module.aks.node_resource_group
}

output "aks_vnet_name" {
  value = module.networking.aks_vnet_name
}

output "clients_vnet_name" {
  value = module.networking.clients_vnet_name
}

output "dns_zone_id" {
  description = "Scope for 'az ad sp create-for-rbac --role DNS Zone Contributor' (see main README section A5) - stable across cluster destroy/apply cycles, since the zone lives outside of Terraform (section A2)"
  value       = module.networking.dns_zone_id
}

output "dns_zone_nameservers" {
  description = "Enter these as NS records for the subdomain at your main DNS provider (e.g. Cloudflare), see main README section A2 - only needed once, when the zone is first created"
  value       = module.networking.dns_zone_nameservers
}
