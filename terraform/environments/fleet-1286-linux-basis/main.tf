# Terraform-managed replacement for scripts/fleet-1286-linux-basis.sh's
# `az vm create` - see terraform/modules/client-vm's own comment for the
# full reasoning (naming compatibility with the downstream fleet-4711/
# destroy-fleet-1286 scripts, ephemeral SSH key since all access happens
# via `az vm run-command`).

data "azurerm_subnet" "clients" {
  name                 = "clients-subnet"
  virtual_network_name = "observability-clients-vnet"
  resource_group_name  = var.resource_group_name
}

module "vm_rocky" {
  source = "../../modules/client-vm"

  vm_name             = "vm-rocky-demo"
  os_type             = "linux"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = data.azurerm_subnet.clients.id

  management_source_ips = ["${data.azurerm_public_ip.ci_runner.ip_address}/32"]
}

# F10: SSH/WinRM only from the GitLab runner (every Ansible job connects
# from there) - looked up by name so a re-created runner IP is picked up
# on the next apply. The runner lives in the same resource group but is
# not managed by this repo.
data "azurerm_public_ip" "ci_runner" {
  name                = var.ci_runner_public_ip_name
  resource_group_name = var.resource_group_name
}
