# cloud-init only reads the seed of a new instance: a change to the cidata
# documents rebuilds the VM instead of swapping the ISO under a running VM.
resource "terraform_data" "jump_host_cloud_init" {
  input = sha256(join("", [module.layout.cloud_init[module.layout.jump_host_name].user_data, module.layout.cloud_init[module.layout.jump_host_name].meta_data, module.layout.cloud_init[module.layout.jump_host_name].network_config]))
}

resource "vsphere_virtual_machine" "jump_host" {
  name             = module.layout.jump_host_name
  annotation       = format("NKP bastion and CAPI bootstrap host (%s)", module.layout.os_label)
  resource_pool_id = data.vsphere_compute_cluster.target.resource_pool_id
  datastore_id     = data.vsphere_datastore.target.id
  folder           = var.vsphere_folder == "" ? null : var.vsphere_folder
  num_cpus         = local.sizing.jump_host_cores
  memory           = local.sizing.jump_host_memory
  guest_id         = local.guest_id
  scsi_type        = "pvscsi"
  enable_disk_uuid = true
  # The Rocky GenericCloud image ships no VMware Tools (Ubuntu ships
  # open-vm-tools): do not wait for a guest IP on either.
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
    size             = local.sizing.jump_host_disk_gb
    thin_provisioned = true
  }
  cdrom {
    datastore_id = data.vsphere_datastore.target.id
    path         = vsphere_file.cidata[module.layout.jump_host_name].destination_file
  }

  clone {
    template_uuid = vsphere_content_library_item.os.id
  }

  lifecycle {
    replace_triggered_by = [terraform_data.os_image, terraform_data.jump_host_cloud_init]
  }
}
