# cloud-init only reads the seed of a new instance: a change to the cidata
# documents rebuilds the VM instead of swapping the ISO under a running VM.
resource "terraform_data" "control_plane_cloud_init" {
  count = length(var.control_plane_ips)
  input = sha256(join("", [module.layout.cloud_init[module.layout.control_plane_names[count.index]].user_data, module.layout.cloud_init[module.layout.control_plane_names[count.index]].meta_data, module.layout.cloud_init[module.layout.control_plane_names[count.index]].network_config]))
}

resource "vsphere_virtual_machine" "control_plane" {
  count            = length(var.control_plane_ips)
  name             = module.layout.control_plane_names[count.index]
  annotation       = format("NKP pre-provisioned control plane node %02d (%s)", count.index + 1, module.layout.os_label)
  resource_pool_id = data.vsphere_compute_cluster.target.resource_pool_id
  datastore_id     = data.vsphere_datastore.target.id
  folder           = var.vsphere_folder == "" ? null : var.vsphere_folder
  num_cpus         = local.sizing.control_plane_cores
  memory           = local.sizing.control_plane_memory
  guest_id         = local.guest_id
  scsi_type        = "pvscsi"
  enable_disk_uuid = true
  # The cloud images carry no VMware Tools: do not wait for a guest IP.
  wait_for_guest_net_timeout = 0
  wait_for_guest_ip_timeout  = 0

  network_interface {
    network_id   = data.vsphere_network.target.id
    adapter_type = "vmxnet3"
  }

  # OS disk only, cloned from the content library item and grown to the
  # profile size.
  disk {
    label            = "os"
    unit_number      = 0
    size             = local.sizing.os_disk_gb
    thin_provisioned = true
  }
  cdrom {
    datastore_id = data.vsphere_datastore.target.id
    path         = vsphere_file.cidata[module.layout.control_plane_names[count.index]].destination_file
  }

  clone {
    template_uuid = vsphere_content_library_item.os.id
  }

  lifecycle {
    replace_triggered_by = [terraform_data.os_image, terraform_data.control_plane_cloud_init[count.index]]
  }
}
