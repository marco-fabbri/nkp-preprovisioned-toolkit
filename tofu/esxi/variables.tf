# The inputs common to every provider are in common_variables.tf, a symbolic
# link to tofu/modules/layout/variables.tf. This file holds the ESXi ones.

# ------------------------------------------------------------------------------
# ESXi host, reached over SSH
# ------------------------------------------------------------------------------

variable "esxi_host" {
  type        = string
  description = "Address of the standalone ESXi host. The module works over SSH (vmkfstools, vim-cmd), so the free licence (vSphere Hypervisor, read-only API) is enough; SSH must be enabled and the operator's public key in /etc/ssh/keys-root/authorized_keys (the SSH agent provides the key, no password is stored)"
}

variable "esxi_ssh_user" {
  type        = string
  default     = "root"
  description = "SSH user on the ESXi host"
}

variable "esxi_ssh_port" {
  type        = number
  default     = 22
  description = "SSH port of the ESXi host"
}

variable "esxi_datastore" {
  type        = string
  default     = "datastore1"
  description = "Datastore of the base disks and of the VMs (spaces allowed, as in \"datastore1 (1)\")"
  validation {
    condition     = length(var.esxi_datastore) > 0 && !can(regex("['/]", var.esxi_datastore))
    error_message = "esxi_datastore must be a datastore name without quotes or slashes."
  }
}

variable "esxi_port_group" {
  type        = string
  default     = "VM Network"
  description = "Port group of the node network"
}

variable "esxi_folder" {
  type        = string
  default     = "nkp"
  description = "Folder on the datastore that holds images/ and one folder per VM; destroy removes only those VM folders and the base disk"
  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9._-]*$", var.esxi_folder))
    error_message = "esxi_folder must be a single folder name: letters, digits, dot, underscore and dash, not starting with a dot or a dash."
  }
}

variable "esxi_virtual_hw_version" {
  type        = number
  default     = 19
  description = "Virtual hardware version of the VMs (19 = ESXi 7.0 U2 and later)"
}

variable "rocky9_image_url" {
  type        = string
  default     = "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  description = "Rocky Linux 9 GenericCloud qcow2 image, downloaded and converted on this computer"
}

variable "ubuntu24_image_url" {
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  description = "Ubuntu 24.04 LTS cloud image (qcow2), downloaded and converted on this computer"
}

# ------------------------------------------------------------------------------
# Names the guest sees (identical on every VM of the cluster)
# ------------------------------------------------------------------------------

variable "guest_nic_name" {
  type        = string
  default     = null
  description = "Name the guest kernel gives the vmxnet3 NIC; virtual_ip_interface in the inventory. Default (measured on ESXi 8): eth0 on Rocky Linux 9 GenericCloud (net.ifnames=0), ens192 on Ubuntu 24.04"
}

variable "guest_ceph_device" {
  type        = string
  default     = "/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:1:0"
  description = "Stable path of the raw Ceph OSD disk (SCSI unit 1) inside the workers; the default is the PVSCSI path measured on ESXi 8, the same on both images"
}

variable "guest_local_volume_devices" {
  type        = list(string)
  default     = ["/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:2:0", "/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:3:0", "/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:4:0", "/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:5:0"]
  description = "Stable paths of the local volume disks (SCSI units 2 to 5) inside the workers, volume 1 to 4"
}
