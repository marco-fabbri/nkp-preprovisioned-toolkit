# Every provider module reads sizing before it creates anything, so the
# checks that span several inputs live here (variable validations only see
# their own variable on OpenTofu 1.6).
output "sizing" {
  description = "VM sizes of the selected profile, disk overrides applied"
  value       = local.sizing
  precondition {
    condition     = length(distinct(values(local.hosts))) == length(local.hosts)
    error_message = "jump_host_ip, control_plane_ips and worker_ips must all be different addresses."
  }
  precondition {
    condition     = !contains(values(local.hosts), var.control_plane_vip)
    error_message = "control_plane_vip must not be the address of a VM: kube-vip moves it between the control plane nodes."
  }
}
output "local_volume_count" {
  value = local.local_volume_count
}
output "os_family" {
  value = local.os_family
}
output "os_label" {
  value = local.os_label
}
output "jump_host_name" {
  value = local.jump_host_name
}
output "control_plane_names" {
  value = local.control_plane_names
}
output "worker_names" {
  value = local.worker_names
}
output "hosts" {
  description = "VM name => IPv4 address, for every VM"
  value       = local.hosts
}
output "cloud_init" {
  description = "VM name => NoCloud user-data, meta-data and network-config"
  value       = local.cloud_init
}
output "user_data_with_network" {
  description = "VM name => user-data that also writes and applies the static address (datasources without a network document)"
  value       = local.user_data_with_network
}
output "ansible_inventory" {
  description = "inventory.ini snippet for the created VMs"
  value = templatefile("${path.module}/inventory.tftpl", {
    jump_host_name       = local.jump_host_name
    jump_host_ip         = var.jump_host_ip
    control_plane_names  = local.control_plane_names
    control_plane_ips    = var.control_plane_ips
    worker_names         = local.worker_names
    worker_ips           = var.worker_ips
    provider_name        = var.provider_name
    os_distribution      = var.os_distribution
    sizing_profile       = var.sizing_profile
    vm_user              = var.vm_user
    os_family            = local.os_family
    control_plane_vip    = var.control_plane_vip
    nic_comment          = var.nic_comment
    nic_name             = var.nic_name
    disk_comment         = local.disk_comment
    ceph_osd_device      = var.ceph_osd_device
    local_volume_devices = var.local_volume_devices
  })
}
