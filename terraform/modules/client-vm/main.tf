# Terraform-managed replacement for the `az vm create` call in
# scripts/fleet-1286-linux-basis.sh/fleet-1229-windows-basis.sh -
# IaC Roadmap milestone, see main README. Deliberately provisioning
# only - no OTel collector/agent install, no app deployment, matching
# the existing split between fleet-* (provisioning) and
# instrumentation-* (Demo Runbook step 4) that this module doesn't
# change - it's instrumentation-1286-linux-basis/
# instrumentation-1229-windows-basis that consume this module's SSH
# key/WinRM password outputs (via `terraform output` against this same
# state) to run Ansible against the VM afterward, a later and fully
# independent CI job.
#
# `az vm create` without an explicit --nic/--nsg auto-creates a NIC,
# Public IP, and NSG (with a default SSH/RDP-only rule) using
# `<vm_name>VMNic`/`<vm_name>PublicIP`/`<vm_name>NSG` naming - this
# module creates the same three resources explicitly (Terraform has no
# equivalent auto-create convenience) with the same names, so
# fleet-4711-mitarbeiterverzeichnis.sh/fleet-4722-spesenabrechnung.sh's
# own `az network nsg rule create --nsg-name <vm_name>NSG` calls (adding
# their own app's public port on top of the base VM, after this module
# already ran) keep working completely unchanged. The base SSH/RDP rule
# is its own azurerm_network_security_rule (not an inline
# security_rule block on the NSG resource itself) specifically so that
# those app-level rules, applied out-of-band via az cli, don't show up
# as drift on this module's own state - Terraform only tracks the rules
# it created as separate resources.

resource "azurerm_public_ip" "this" {
  name                = "${var.vm_name}PublicIP"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "this" {
  name                = "${var.vm_name}NSG"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Management access (F10). SSH (Linux) and WinRM (Windows) are reachable
# only from management_source_ips (the GitLab runner's public IP - every
# Ansible job connects to the VM's public IP from there) plus the
# VirtualNetwork service tag (peered VNets: OpenClaw in AKS reaches
# vm-rocky-demo's private IP). A service tag can't be combined with IPs
# in one rule, hence two rules.
#
# RDP (Windows) stays open to any source: a deliberate, accepted demo
# exception (interactive presenter access from changing networks, password
# login against a random 20-character admin password) - see the README's
# "Accepted exceptions".
#trivy:ignore:AZU-0047
#trivy:ignore:AZU-0048
resource "azurerm_network_security_rule" "base_access" {
  name                        = var.os_type == "linux" ? "AllowSSHInbound" : "AllowRDPInbound"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = var.os_type == "linux" ? "22" : "3389"
  source_address_prefix       = var.os_type == "linux" ? null : "*"
  source_address_prefixes     = var.os_type == "linux" ? var.management_source_ips : null
  destination_address_prefix  = "*"
}

resource "azurerm_network_security_rule" "management_vnet" {
  name                        = var.os_type == "linux" ? "AllowSSHFromVirtualNetwork" : "AllowWinRMHttpsFromVirtualNetwork"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this.name
  priority                    = 105
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = var.os_type == "linux" ? "22" : "5986"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
}

# WinRM (HTTPS, 5986) - the port the winrm_https_setup extension below
# configures. Windows-only, alongside the RDP base rule above.
resource "azurerm_network_security_rule" "winrm_https" {
  count                       = var.os_type == "windows" ? 1 : 0
  name                        = "AllowWinRMHttpsInbound"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this.name
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5986"
  source_address_prefixes     = var.management_source_ips
  destination_address_prefix  = "*"
}

resource "azurerm_network_interface" "this" {
  name                = "${var.vm_name}VMNic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# Generated by Terraform, not by hand - and, since the IaC Roadmap
# Ansible milestone, genuinely used afterward (Ansible connects over
# SSH/WinRM using exactly these, fetched via this module's own sensitive
# outputs) rather than being immediately discarded. Provisioning
# (fleet-*, this module) still never uses them directly - fleet-* jobs
# still talk to the VM via `az vm run-command` only, same as before -
# it's the later, independent instrumentation-* jobs that pick these up.
resource "tls_private_key" "linux_ssh" {
  count     = var.os_type == "linux" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "random_password" "windows_admin" {
  count   = var.os_type == "windows" ? 1 : 0
  length  = 20
  special = true
  # No "#" - found live: the deploy-fleets:*/deploy-instrumentations:*
  # Windows jobs embed this password unquoted in a generated Ansible INI
  # inventory line alongside ansible_connection=winrm (see
  # .gitlab-ci.yml's "cat > ansible/inventory/generated.ini" heredocs) -
  # "#" starts a comment in Ansible's INI inventory parser, silently
  # truncating everything after it on that line whenever the randomly
  # generated password happened to contain one, dropping
  # ansible_connection=winrm entirely. Ansible then defaulted to its own
  # "ssh" connection type, which isn't even installed in these
  # Windows-only job containers - "Unable to execute ssh command line on
  # a controller: No such file or directory: b'ssh'".
  override_special = "!@%^"
}

resource "azurerm_linux_virtual_machine" "this" {
  count                 = var.os_type == "linux" ? 1 : 0
  name                  = var.vm_name
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.vm_size
  admin_username        = var.linux_admin_username
  network_interface_ids = [azurerm_network_interface.this.id]

  source_image_id = var.linux_image_id

  admin_ssh_key {
    username   = var.linux_admin_username
    public_key = tls_private_key.linux_ssh[0].public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    # Explicit, larger than the marketplace image's own default (10 GB) -
    # found live: vm-rocky-demo (this module's only Linux instance,
    # hosting both 1286's own workload and, since the UC4 pivot, 4711's
    # Tomcat app) filled its OS disk solely from `az vm run-command`
    # invocations accumulating settings files under
    # /var/lib/waagent/Microsoft.CPlat.Core.RunCommandLinux-*/config/ -
    # every demo break/fix job and manual debugging call this whole repo
    # relies on goes through that mechanism, and once the disk fills, the
    # RunCommand extension itself can't even report an error cleanly
    # (`No space left on device` writing its own settings file), wedging
    # every future invocation behind a permanent
    # "Run command extension execution is in progress" conflict with no
    # self-recovery - fixed live via the Azure Serial Console (bypasses
    # the wedged extension entirely) while the VM was stopped to resize
    # this disk.
    disk_size_gb = 30
  }
}

resource "azurerm_windows_virtual_machine" "this" {
  count                 = var.os_type == "windows" ? 1 : 0
  name                  = var.vm_name
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.vm_size
  admin_username        = var.windows_admin_username
  admin_password        = random_password.windows_admin[0].result
  network_interface_ids = [azurerm_network_interface.this.id]

  source_image_reference {
    publisher = var.windows_image_publisher
    offer     = var.windows_image_offer
    sku       = var.windows_image_sku
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}

# WinRM is not enabled by default on a fresh Windows Server image. This
# extension does the minimal setup inline (the same steps Ansible's
# ConfigureRemotingForAnsible.ps1 took, minus its listener/cert part):
# WinRM service + PS remoting, Basic auth (only over the HTTPS listener -
# see the IaC Roadmap Ansible milestone for why HTTPS, given the public
# IP), LocalAccountTokenFilterPolicy for the local admin, and a firewall
# rule for 5986. The HTTPS listener and its certificate come from the
# pin-winrm-cert run command below.
#
# Inline instead of downloading ConfigureRemotingForAnsible.ps1 from the
# ansible-documentation repo's devel branch at runtime: that ran whatever
# the branch contained at VM creation time, as SYSTEM, unpinned and
# unverified. The script is idempotent - changing it re-runs it on the
# existing VM without touching the pinned listener.
locals {
  winrm_setup_script = <<-EOT
    $ErrorActionPreference = "Stop"
    Set-Service -Name WinRM -StartupType Automatic
    Start-Service -Name WinRM
    Enable-PSRemoting -SkipNetworkProfileCheck -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System `
      -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWORD -Force | Out-Null
    if (-not (Get-NetFirewallRule -Name WinRM-HTTPS-In -ErrorAction SilentlyContinue)) {
      New-NetFirewallRule -Name WinRM-HTTPS-In -DisplayName "Allow WinRM HTTPS" -Direction Inbound `
        -Protocol TCP -LocalPort 5986 -Action Allow -Profile Any | Out-Null
    }
  EOT
}

resource "azurerm_virtual_machine_extension" "winrm_https_setup" {
  count                = var.os_type == "windows" ? 1 : 0
  name                 = "winrm-https-setup"
  virtual_machine_id   = azurerm_windows_virtual_machine.this[0].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # Explicitly empty: when settings is omitted, the provider sends nothing
  # and Azure keeps the old public settings - found live, the former
  # fileUris (ConfigureRemotingForAnsible.ps1 from the devel branch) stayed
  # on the extension and would be downloaded again on every run.
  settings = jsonencode({})

  protected_settings = jsonencode({
    commandToExecute = "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(local.winrm_setup_script, "UTF-16LE")}"
  })
}

# F08: the SSH host key, read over the Azure control plane (authenticated
# ARM API, independent of the network path Ansible/OpenClaw later use).
# Exposed as an output; the CI jobs write it into known_hosts and connect
# with StrictHostKeyChecking=yes instead of trusting whatever key answers.
# Re-created with the VM; if the host key ever changes otherwise,
# `terraform apply -replace=module.vm_rocky.azurerm_virtual_machine_run_command.ssh_host_key[0]`
# reads it again.
resource "azurerm_virtual_machine_run_command" "ssh_host_key" {
  count              = var.os_type == "linux" ? 1 : 0
  name               = "read-ssh-host-key"
  location           = var.location
  virtual_machine_id = azurerm_linux_virtual_machine.this[0].id

  source {
    script = "cut -d' ' -f1-2 /etc/ssh/ssh_host_ed25519_key.pub"
  }
}

# F08: creates the WinRM HTTPS listener (or, on VMs bootstrapped by the
# former ConfigureRemotingForAnsible.ps1, replaces its certificate, which
# only named the computer and never matched the public IP Ansible
# connects to) with a self-signed certificate that has the VM's public IP
# as SAN. The key is generated on the VM
# and stays there; only the public certificate comes back as this run
# command's output. The CI jobs pin it (ansible_winrm_ca_trust_path) and
# validate the server certificate instead of ignoring it.
resource "azurerm_virtual_machine_run_command" "winrm_cert" {
  count              = var.os_type == "windows" ? 1 : 0
  name               = "pin-winrm-cert"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this[0].id

  source {
    script = <<-EOT
      $ErrorActionPreference = "Stop"
      $ip = "${azurerm_public_ip.this.ip_address}"
      $name = "${var.vm_name}"
      $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
        $_.FriendlyName -eq "winrm-pinned-$ip" -and $_.NotAfter -gt (Get-Date).AddDays(30)
      } | Sort-Object NotAfter -Descending | Select-Object -First 1
      if (-not $cert) {
        $cert = New-SelfSignedCertificate -CertStoreLocation Cert:\LocalMachine\My `
          -Subject "CN=$name" -FriendlyName "winrm-pinned-$ip" `
          -TextExtension @("2.5.29.17={text}IPAddress=$ip&DNS=$name", "2.5.29.37={text}1.3.6.1.5.5.7.3.1") `
          -KeyAlgorithm RSA -KeyLength 2048 -NotAfter (Get-Date).AddYears(3)
      }
      $listener = Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTPS" }
      if ($listener) {
        Set-Item -Path (Join-Path $listener.PSPath "CertificateThumbprint") -Value $cert.Thumbprint -Force
      } else {
        New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null
      }
      Restart-Service WinRM
      "-----BEGIN CERTIFICATE-----"
      [Convert]::ToBase64String($cert.RawData, "InsertLineBreaks")
      "-----END CERTIFICATE-----"
    EOT
  }

  depends_on = [azurerm_virtual_machine_extension.winrm_https_setup]
}
