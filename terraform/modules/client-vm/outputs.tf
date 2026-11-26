output "vm_name" {
  value = var.vm_name
}

output "public_ip_address" {
  value = azurerm_public_ip.this.ip_address
}

output "nsg_name" {
  value = azurerm_network_security_group.this.name
}

# Consumed by instrumentation-1286-linux-basis/instrumentation-1229-
# windows-basis (Ansible, IaC Roadmap milestone) via `terraform output`
# against this same state - null for the other os_type, same
# count-gated pattern as the underlying resources.
output "ssh_private_key_openssh" {
  value     = var.os_type == "linux" ? tls_private_key.linux_ssh[0].private_key_openssh : null
  sensitive = true
}

output "admin_username" {
  value = var.os_type == "linux" ? var.linux_admin_username : var.windows_admin_username
}

output "admin_password" {
  value     = var.os_type == "windows" ? random_password.windows_admin[0].result : null
  sensitive = true
}

# F08: pinned server identities, see the run commands in main.tf. regex()
# fails the apply loudly if the output isn't what's expected.
output "ssh_host_public_key" {
  value = var.os_type == "linux" ? regex("ssh-ed25519 [A-Za-z0-9+/=]+", azurerm_virtual_machine_run_command.ssh_host_key[0].instance_view[0].output) : null
}

output "winrm_server_cert_pem" {
  value = var.os_type == "windows" ? "${regex("-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\\s]+-----END CERTIFICATE-----", azurerm_virtual_machine_run_command.winrm_cert[0].instance_view[0].output)}\n" : null
}
