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

  provider_name        = "proxmox"
  nic_name             = "eth0"
  nic_comment          = "The Proxmox cloud-init network config names the first NIC eth0 on both images"
  disk_comment         = <<-EOT
    Worker disks created by this module, named by their serial number through
    the stable /dev/disk/by-id links (kernel names such as sdb do not follow the
    SCSI slot and can change at reboot): nkp-ceph = raw Ceph OSD
    ({ceph_gb} GB), nkp-vol1..nkp-vol4 = local volumes 1..4
    ({volume_gb} GB each)
  EOT
  ceph_osd_device      = "/dev/disk/by-id/scsi-SQEMU_QEMU_HARDDISK_nkp-ceph"
  local_volume_devices = [for i in range(4) : format("/dev/disk/by-id/scsi-SQEMU_QEMU_HARDDISK_nkp-vol%d", i + 1)]
}
