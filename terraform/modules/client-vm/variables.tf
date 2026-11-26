variable "vm_name" {
  type        = string
  description = "Azure resource name for the VM - also used to derive the NIC/public IP/NSG names (<vm_name>VMNic/PublicIP/NSG), matching the naming `az vm create` used to generate automatically, so fleet-*/destroy-fleet-* scripts that reference these by name (e.g. to add an app-specific NSG rule) keep working unchanged."
}

variable "os_type" {
  type        = string
  description = "\"linux\" or \"windows\" - selects which VM resource, image, and base NSG rule (SSH vs RDP) this module creates."
  validation {
    condition     = contains(["linux", "windows"], var.os_type)
    error_message = "os_type must be \"linux\" or \"windows\"."
  }
}

variable "resource_group_name" {
  type    = string
  default = "rg-bensc-001"
}

variable "location" {
  type    = string
  default = "switzerlandnorth"
}

variable "subnet_id" {
  type        = string
  description = "The clients-subnet ID (terraform/modules/networking, looked up via a data source in the calling environment - see that environment's own comment for why not a direct module reference)."
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

# --- linux-specific (ignored when os_type = "windows") ---

variable "linux_image_id" {
  type        = string
  description = "Full Azure Compute Gallery image ID. Default is this demo's Rocky Linux 9.4 community gallery image. Segment casing matters here even though it doesn't for `az vm create --image` (found live: azurerm_linux_virtual_machine's source_image_id parser is case-sensitive and rejects the /CommunityGalleries/.../Images/.../Versions/... casing the Azure CLI/portal display, requiring /communityGalleries/.../images/.../versions/... instead)."
  default     = "/communityGalleries/rocky-dc1c6aa6-905b-4d9c-9577-63ccc28c482a/images/Rocky-9-x86_64/versions/9.4.20240509"
}

variable "linux_admin_username" {
  type    = string
  default = "rocky"
}

# --- windows-specific (ignored when os_type = "linux") ---

variable "windows_image_publisher" {
  type    = string
  default = "MicrosoftWindowsServer"
}

variable "windows_image_offer" {
  type    = string
  default = "WindowsServer"
}

variable "windows_image_sku" {
  type    = string
  default = "2022-datacenter-azure-edition"
}

variable "windows_admin_username" {
  type    = string
  default = "azureuser"
}

variable "management_source_ips" {
  type        = list(string)
  description = "Public source IPs/CIDRs allowed to reach SSH (Linux) or WinRM (Windows) - the GitLab runner's egress IP (F10). Peered VNets are allowed separately via the VirtualNetwork service tag."
  validation {
    condition     = length(var.management_source_ips) > 0 && !contains(var.management_source_ips, "*") && !contains(var.management_source_ips, "0.0.0.0/0")
    error_message = "management_source_ips must list specific IPs/CIDRs, not any source."
  }
}
