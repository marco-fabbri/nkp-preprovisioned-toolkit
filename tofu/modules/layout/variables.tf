# Inputs common to every provider module. This file is the single definition:
# each tofu/<provider>/common_variables.tf is a symbolic link to it, so the
# root modules and this module validate the same inputs the same way.

variable "os_distribution" {
  type        = string
  default     = "rocky9"
  description = "Cloud image installed on every VM: rocky9 or ubuntu24 (deploy.sh derives it from os_profile in inventory.ini)"
  validation {
    condition     = contains(["rocky9", "ubuntu24"], var.os_distribution)
    error_message = "os_distribution must be rocky9 or ubuntu24."
  }
}

variable "sizing_profile" {
  type        = string
  default     = "pro-ultimate"
  description = "VM sizes and disk layout: pro-ultimate (Pro and Ultimate requirements of the NKP 2.18 guide, the sizes the Ansible preflight checks) or contract-test (tiny VMs for ./deploy.sh tofu-verify only, no NKP installation). deploy.sh passes tofu_sizing_profile from inventory.ini when set"
  validation {
    condition     = contains(["pro-ultimate", "contract-test"], var.sizing_profile)
    error_message = "sizing_profile must be pro-ultimate or contract-test."
  }
}

variable "jump_host_ip" {
  type        = string
  description = "Static IPv4 address of the jump host (for example 10.10.10.80)"
  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", var.jump_host_ip))
    error_message = "jump_host_ip must be an IPv4 address such as 10.10.10.80."
  }
}

variable "control_plane_ips" {
  type        = list(string)
  description = "Static IPv4 addresses of the control plane nodes: 1 or 3 (3 for an etcd quorum), for example [\"10.10.10.81\", \"10.10.10.82\", \"10.10.10.83\"]"
  validation {
    condition     = contains([1, 3], length(var.control_plane_ips))
    error_message = "control_plane_ips must list 1 or 3 addresses."
  }
  validation {
    condition     = alltrue([for ip in var.control_plane_ips : can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", ip))])
    error_message = "control_plane_ips must list IPv4 addresses such as 10.10.10.81."
  }
}

variable "control_plane_vip" {
  type        = string
  description = "Virtual IP of the control plane endpoint, managed by kube-vip; an unused address in the node subnet (for example 10.10.10.85). Not assigned to any VM, only exported to the inventory"
  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", var.control_plane_vip))
    error_message = "control_plane_vip must be an IPv4 address such as 10.10.10.85."
  }
}

variable "worker_ips" {
  type        = list(string)
  description = "Static IPv4 addresses of the worker nodes; one worker VM per address. The NKP guide lists 4 workers for Pro and Ultimate clusters; the count is not enforced"
  validation {
    condition     = length(var.worker_ips) >= 1
    error_message = "worker_ips must list at least one address."
  }
  validation {
    condition     = alltrue([for ip in var.worker_ips : can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", ip))])
    error_message = "worker_ips must list IPv4 addresses such as 10.10.10.86."
  }
}

variable "network_gateway" {
  type        = string
  description = "Default gateway of the node subnet"
  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", var.network_gateway))
    error_message = "network_gateway must be an IPv4 address such as 10.10.10.1."
  }
}

variable "network_prefix_length" {
  type        = number
  default     = 24
  description = "Prefix length of the node subnet (24 for a /24)"
  validation {
    condition     = var.network_prefix_length >= 8 && var.network_prefix_length <= 30
    error_message = "network_prefix_length must be between 8 and 30."
  }
}

variable "dns_servers" {
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
  description = "DNS servers configured on every VM"
  validation {
    condition     = length(var.dns_servers) > 0 && alltrue([for ip in var.dns_servers : can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", ip))])
    error_message = "dns_servers must list at least one IPv4 address."
  }
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key authorised for vm_user on every VM through cloud-init"
}

variable "vm_user" {
  type        = string
  default     = "nutanix"
  description = "OS user created by cloud-init on every VM (passwordless sudo); the same value as ansible_user in inventory.ini"
}

variable "ceph_disk_size_gb" {
  type        = number
  default     = null
  description = "Size in GB of the raw Ceph OSD disk of every worker (second disk). Default: 50 for pro-ultimate, 5 for contract-test. NKP requires at least 40 GiB"
}

variable "local_volume_size_gb" {
  type        = number
  default     = null
  description = "Size in GB of each of the 4 local volume disks of every worker (disks 3 to 6). Default: 110 for pro-ultimate, 5 for contract-test. NKP needs more than 100 GiB: Prometheus claims exactly 100 GiB and the file system is a little smaller than the disk"
}
