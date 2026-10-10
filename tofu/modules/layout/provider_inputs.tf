# Inputs that only the calling provider module knows.

variable "provider_name" {
  type        = string
  description = "Directory of the calling module under tofu/ (proxmox, esxi, vsphere, nutanix), named in the inventory header"
}

variable "nic_name" {
  type        = string
  description = "Name the guest kernel gives the VM network interface on this hypervisor: virtual_ip_interface in the inventory and the interface of the cloud-init network config"
}

variable "nic_comment" {
  type        = string
  description = "One inventory comment line (without the leading '# ') explaining nic_name"
}

variable "disk_comment" {
  type        = string
  description = "Inventory comment lines (without the leading '# ') explaining how the worker disks are identified; {ceph_gb} and {volume_gb} are replaced with the disk sizes"
}

variable "ceph_osd_device" {
  type        = string
  description = "Stable path of the raw Ceph OSD disk, the same on every worker"
}

variable "local_volume_devices" {
  type        = list(string)
  description = "Stable paths of the 4 local volume disks, volume 1 to 4, the same on every worker"
  validation {
    condition     = length(var.local_volume_devices) == 4
    error_message = "local_volume_devices must list exactly 4 paths."
  }
}
