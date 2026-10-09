# cloud-init only reads the seed of a new instance: a change to the cidata
# documents rebuilds the VM instead of swapping the ISO under a running VM.
resource "terraform_data" "worker_cloud_init" {
  count = length(var.worker_ips)
  input = sha256(join("", [module.layout.cloud_init[module.layout.worker_names[count.index]].user_data, module.layout.cloud_init[module.layout.worker_names[count.index]].meta_data, module.layout.cloud_init[module.layout.worker_names[count.index]].network_config]))
}

resource "vsphere_virtual_machine" "worker" {
  count            = length(var.worker_ips)
  name             = module.layout.worker_names[count.index]
  annotation       = format("NKP pre-provisioned worker node %02d (%s)", count.index + 1, module.layout.os_label)
  resource_pool_id = data.vsphere_compute_cluster.target.resource_pool_id
  datastore_id     = data.vsphere_datastore.target.id
  folder           = var.vsphere_folder == "" ? null : var.vsphere_folder
  num_cpus         = local.sizing.worker_cores
  memory           = local.sizing.worker_memory
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

  # unit 0 = OS, 1 = raw Ceph OSD, 2..5 = local volumes; the inventory names
  # them by SCSI slot (by-path).
  disk {
    label            = "os"
    unit_number      = 0
    size             = local.sizing.os_disk_gb
    thin_provisioned = true
  }
  disk {
    label            = "ceph"
    unit_number      = 1
    size             = local.sizing.ceph_disk_gb
    thin_provisioned = true
  }
  dynamic "disk" {
    for_each = range(module.layout.local_volume_count)
    content {
      label            = format("vol%d", disk.value + 1)
      unit_number      = disk.value + 2
      size             = local.sizing.local_volume_gb
      thin_provisioned = true
    }
  }

  cdrom {
    datastore_id = data.vsphere_datastore.target.id
    path         = vsphere_file.cidata[module.layout.worker_names[count.index]].destination_file
  }

  clone {
    template_uuid = vsphere_content_library_item.os.id
  }

  lifecycle {
    replace_triggered_by = [terraform_data.os_image, terraform_data.worker_cloud_init[count.index]]
  }
}
