module "layout" {
  source = "../modules/layout"

  os_distribution       = var.os_distribution
  sizing_profile        = var.sizing_profile
  jump_host_ip          = var.jump_host_ip
  control_plane_ips     = var.control_plane_ips
  control_plane_vip     = var.control_plane_vip
  worker_ips            = var.worker_ips
  network_gateway       = var.network_gateway
  network_prefix_length = var.network_prefix_length
  dns_servers           = var.dns_servers
  ssh_public_key        = var.ssh_public_key
  vm_user               = var.vm_user
  ceph_disk_size_gb     = var.ceph_disk_size_gb
  local_volume_size_gb  = var.local_volume_size_gb

  provider_name        = "nutanix"
  nic_name             = local.guest_nic_name
  nic_comment          = "Name the guest kernel gives the AHV virtio NIC: eth0 on Rocky GenericCloud (net.ifnames=0), ens3 on Ubuntu"
  disk_comment         = <<-EOT
    Worker disks created by this module, named by their SCSI slot through the
    stable /dev/disk/by-path links (AHV does not let the module set a disk
    serial; kernel names such as sdb can change at reboot): slot 1 = raw Ceph
    OSD ({ceph_gb} GB), slots 2..5 = local volumes 1..4 ({volume_gb} GB each)
  EOT
  ceph_osd_device      = var.guest_ceph_device
  local_volume_devices = var.guest_local_volume_devices
}
