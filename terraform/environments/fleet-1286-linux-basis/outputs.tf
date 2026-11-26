# Consumed by instrumentation-1286-linux-basis (Ansible) via
# `terraform output -raw ssh_private_key`/`terraform output -raw
# admin_username` against this same state.
output "ssh_private_key" {
  value     = module.vm_rocky.ssh_private_key_openssh
  sensitive = true
}

output "admin_username" {
  value = module.vm_rocky.admin_username
}

output "public_ip_address" {
  value = module.vm_rocky.public_ip_address
}

# F08: pinned server identity for the CI jobs (see modules/client-vm).
output "ssh_host_public_key" {
  value = module.vm_rocky.ssh_host_public_key
}
