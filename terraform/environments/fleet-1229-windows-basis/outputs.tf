# Consumed by instrumentation-1229-windows-basis (Ansible) via
# `terraform output -raw admin_password`/`terraform output -raw
# admin_username` against this same state.
output "admin_username" {
  value = module.vm_windows.admin_username
}

output "admin_password" {
  value     = module.vm_windows.admin_password
  sensitive = true
}

output "public_ip_address" {
  value = module.vm_windows.public_ip_address
}

# F08: pinned server identity for the CI jobs (see modules/client-vm).
output "winrm_server_cert_pem" {
  value = module.vm_windows.winrm_server_cert_pem
}
