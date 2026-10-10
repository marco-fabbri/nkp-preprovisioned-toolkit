# The inputs common to every provider are in common_variables.tf, a symbolic
# link to tofu/modules/layout/variables.tf. This file holds the Proxmox ones.

# ------------------------------------------------------------------------------
# Proxmox specific inputs
# ------------------------------------------------------------------------------

variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox VE API endpoint (for example https://pve.example.com:8006/)"
}

variable "proxmox_insecure" {
  type        = bool
  default     = true
  description = "Skip TLS verification of the API endpoint (self-signed Proxmox certificates)"
}

variable "proxmox_api_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Proxmox API token (USER@REALM!TOKENID=UUID); leave empty to authenticate with username and password"
}

variable "proxmox_username" {
  type        = string
  default     = ""
  description = "Proxmox user (for example root@pam) when no API token is given"
}

variable "proxmox_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Proxmox password when no API token is given"
}

variable "proxmox_ssh_username" {
  type        = string
  default     = "root"
  description = "SSH user on the Proxmox node, reached through the local SSH agent for the operations the API does not cover (disk import)"
}

variable "proxmox_node" {
  type        = string
  default     = "pve"
  description = "Proxmox node that hosts every VM"
}

variable "datastore_id" {
  type        = string
  default     = "local-lvm"
  description = "Datastore of the VM disks (for example local-lvm, local-zfs or a Ceph RBD pool). Thin allocation depends on this datastore"
}

variable "image_datastore" {
  type        = string
  default     = "local"
  description = "Datastore that stores the downloaded cloud images; it must allow the import content type"
}

variable "template_file_id" {
  type        = string
  default     = ""
  description = "Optional ID of a cloud image already present on Proxmox (for example local:import/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2); when set, it is used for os_distribution instead of the downloaded image"
}

variable "rocky9_image_url" {
  type        = string
  default     = "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  description = "Download URL of the Rocky Linux 9 GenericCloud image"
}

variable "ubuntu24_image_url" {
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  description = "Download URL of the Ubuntu 24.04 LTS cloud image"
}

variable "network_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Proxmox bridge the VM NICs attach to"
}

variable "network_vlan_id" {
  type        = number
  default     = null
  description = "Optional VLAN tag of the VM NICs"
}

variable "vm_id_base" {
  type        = number
  default     = 800
  description = "First Proxmox VM ID: jump host = base, control planes = base+1..base+3, workers = base+4 onwards"
}
