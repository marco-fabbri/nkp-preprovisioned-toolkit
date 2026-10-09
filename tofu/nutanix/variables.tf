# The inputs common to every provider are in common_variables.tf, a symbolic
# link to tofu/modules/layout/variables.tf. This file holds the Nutanix ones.

# ------------------------------------------------------------------------------
# Prism Central access
# ------------------------------------------------------------------------------

variable "nutanix_endpoint" {
  type        = string
  description = "Prism Central address (IP or FQDN, without scheme or port)"
}

variable "nutanix_port" {
  type        = number
  default     = 9440
  description = "Prism Central API port"
}

variable "nutanix_username" {
  type        = string
  description = "Prism Central user allowed to create images and VMs on the target cluster"
}

variable "nutanix_password" {
  type        = string
  sensitive   = true
  description = "Password of nutanix_username"
}

variable "nutanix_insecure" {
  type        = bool
  default     = false
  description = "Skip the TLS certificate check of Prism Central (self-signed lab certificates)"
}

# ------------------------------------------------------------------------------
# Placement
# ------------------------------------------------------------------------------

variable "nutanix_cluster_name" {
  type        = string
  description = "Name of the AHV cluster, as registered in Prism Central, that runs the VMs"
}

variable "nutanix_subnet_name" {
  type        = string
  description = "Name of the AHV subnet of the node network. The addresses are static (cloud-init); with IPAM set nutanix_subnet_ipam = true"
}

variable "nutanix_subnet_ipam" {
  type        = bool
  default     = false
  description = "true when nutanix_subnet_name has AHV IPAM: each VM address is then also reserved on AHV, so that the subnet's DHCP pool cannot give it to another VM. The VM addresses must lie inside one of the subnet's IP pools: AHV accepts a reservation outside the pools at creation but refuses to power the VM on (\"no host has enough resources\", seen on PC 7.6). Keep control_plane_vip and the MetalLB range outside the pools, where the DHCP server never hands them out"
}

variable "nutanix_storage_container_name" {
  type        = string
  default     = ""
  description = "Storage container of the data disks; empty = the cluster default"
}

variable "rocky9_image_url" {
  type        = string
  default     = "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  description = "Rocky Linux 9 GenericCloud qcow2 image; Prism Central downloads it, so it must be reachable from Prism Central"
}

variable "ubuntu24_image_url" {
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  description = "Ubuntu 24.04 LTS cloud image (qcow2); Prism Central downloads it, so it must be reachable from Prism Central"
}

# ------------------------------------------------------------------------------
# Names the guest sees (identical on every VM of the cluster)
# ------------------------------------------------------------------------------

variable "guest_nic_name" {
  type        = string
  default     = null
  description = "Name the guest kernel gives the AHV virtio NIC; virtual_ip_interface in the inventory. Default (measured on AHV): eth0 on Rocky Linux 9 GenericCloud (booted with net.ifnames=0), ens3 on Ubuntu 24.04"
}

variable "guest_ceph_device" {
  type        = string
  default     = "/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:1:0"
  description = "Stable path of the raw Ceph OSD disk (SCSI index 1) inside the workers; the default is the AHV virtio-scsi path, the same on both images"
}

variable "guest_local_volume_devices" {
  type        = list(string)
  default     = ["/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:2:0", "/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:3:0", "/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:4:0", "/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:5:0"]
  description = "Stable paths of the local volume disks (SCSI index 2 to 5) inside the workers, volume 1 to 4; the defaults are the AHV virtio-scsi paths"
}
