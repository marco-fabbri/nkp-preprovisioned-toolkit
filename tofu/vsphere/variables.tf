# The inputs common to every provider are in common_variables.tf, a symbolic
# link to tofu/modules/layout/variables.tf. This file holds the vSphere ones.

# ------------------------------------------------------------------------------
# vCenter access
# ------------------------------------------------------------------------------

variable "vsphere_server" {
  type        = string
  description = "vCenter address (FQDN or IP). vCenter is required: cloning from a content library is a vCenter feature"
}

variable "vsphere_user" {
  type        = string
  description = "vCenter user allowed to manage a content library, upload to the datastore and create VMs in the cluster"
}

variable "vsphere_password" {
  type        = string
  sensitive   = true
  description = "Password of vsphere_user"
}

variable "vsphere_insecure" {
  type        = bool
  default     = false
  description = "Skip the TLS certificate check of vCenter (self-signed lab certificates)"
}

# ------------------------------------------------------------------------------
# Placement
# ------------------------------------------------------------------------------

variable "vsphere_datacenter" {
  type        = string
  description = "Datacenter that holds the cluster, the datastore and the network"
}

variable "vsphere_cluster" {
  type        = string
  description = "Compute cluster that runs the VMs (its root resource pool is used)"
}

variable "vsphere_datastore" {
  type        = string
  description = "Datastore of the VM disks, the content library and the cidata ISOs"
}

variable "vsphere_network" {
  type        = string
  description = "Port group of the node network. kube-vip and MetalLB answer ARP for addresses no NIC owns, with the VM's own MAC, so the default security policy of a standard vSwitch should allow it (not verified); ./deploy.sh tofu-verify tests the VIP path"
}

variable "vsphere_folder" {
  type        = string
  default     = ""
  description = "VM folder, relative to the datacenter; empty = the datacenter root"
}

variable "vsphere_content_library" {
  type        = string
  default     = "nkp-images"
  description = "Name of the local content library the module creates for the OS image"
}

variable "rocky9_image_url" {
  type        = string
  default     = "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  description = "Rocky Linux 9 GenericCloud qcow2 image, downloaded on this computer and turned into an OVA"
}

variable "ubuntu24_image_url" {
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  description = "Ubuntu 24.04 LTS cloud image (qcow2), downloaded on this computer and turned into an OVA"
}

# ------------------------------------------------------------------------------
# Names the guest sees (identical on every VM of the cluster)
# ------------------------------------------------------------------------------

variable "guest_nic_name" {
  type        = string
  default     = null
  description = "Name the guest kernel gives the vmxnet3 NIC; virtual_ip_interface in the inventory and the interface of the cloud-init network config. Default (measured on vCenter 8.0U3): eth0 on Rocky Linux 9 GenericCloud (net.ifnames=0), ens192 on Ubuntu 24.04"
}

variable "guest_ceph_device" {
  type        = string
  default     = "/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:1:0"
  description = "Stable path of the raw Ceph OSD disk (SCSI unit 1) inside the workers; the default is the PVSCSI path measured on vCenter 8.0U3, the same on both images"
}

variable "guest_local_volume_devices" {
  type        = list(string)
  default     = ["/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:2:0", "/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:3:0", "/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:4:0", "/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:5:0"]
  description = "Stable paths of the local volume disks (SCSI units 2 to 5) inside the workers, volume 1 to 4"
}
