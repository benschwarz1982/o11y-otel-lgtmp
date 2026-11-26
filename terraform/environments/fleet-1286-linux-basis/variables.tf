variable "resource_group_name" {
  type    = string
  default = "rg-bensc-001"
}

variable "location" {
  type    = string
  default = "switzerlandnorth"
}

variable "ci_runner_public_ip_name" {
  type        = string
  default     = "mgmt-gitlab-runner-pip"
  description = "Name of the GitLab runner VM's public IP resource (same resource group) - the only internet source allowed to reach SSH/WinRM (F10)."
}
