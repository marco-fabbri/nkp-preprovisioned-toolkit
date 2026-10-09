resource "proxmox_virtual_environment_vm" "worker" {
  count       = length(var.worker_ips)
  name        = format("nkp-worker-%02d", count.index + 1)
  description = format("NKP pre-provisioned worker node %02d (%s)", count.index + 1, local.os_label)
  node_name   = var.proxmox_node
  vm_id       = var.vm_id_base + 4 + count.index

  # The cloud images do not ship the QEMU guest agent: with it enabled the
  # provider waits 15 minutes for an answer on every refresh and creation.
  agent {
    enabled = false
  }

  cpu {
    cores = local.sizing.worker_cores
    type  = "host"
  }

  memory {
    dedicated = local.sizing.worker_memory
  }

  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  # scsi0 = OS, scsi1 = Ceph OSD, scsi2..scsi5 = local volumes. The guest
  # kernel does NOT name them in interface order (seen in the lab: scsi2 came
  # up as sdb, scsi1 as sdc), and kernel names can change at reboot. Each data
  # disk therefore carries a serial number, exposed by udev as
  # /dev/disk/by-id/scsi-SQEMU_QEMU_HARDDISK_<serial>: the ansible_inventory
  # output names the disks through these links.
  disk {
    datastore_id = var.datastore_id
    import_from  = local.os_image_id
    interface    = "scsi0"
    size         = local.sizing.os_disk_gb
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  # Raw block device handed to Rook Ceph (ceph_osd_device =
  # /dev/disk/by-id/scsi-SQEMU_QEMU_HARDDISK_nkp-ceph): no partition table and
  # no file system are ever created on it.
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi1"
    size         = local.ceph_disk_gb
    file_format  = "raw"
    discard      = "on"
    ssd          = true
    iothread     = true
    serial       = "nkp-ceph"
  }

  # Local volumes for the local static provisioner (local_volume_devices =
  # the by-id links of nkp-vol1..nkp-vol4, volume N = serial nkp-volN): the
  # toolkit formats them whole and mounts them by UUID under /mnt/disks/.
  dynamic "disk" {
    for_each = range(local.local_volume_count)
    content {
      datastore_id = var.datastore_id
      interface    = format("scsi%d", disk.value + 2)
      size         = local.local_volume_gb
      file_format  = "raw"
      discard      = "on"
      ssd          = true
      iothread     = true
      serial       = format("nkp-vol%d", disk.value + 1)
    }
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.network_vlan_id
    model   = "virtio"
  }

  initialization {
    datastore_id = var.datastore_id
    ip_config {
      ipv4 {
        address = "${var.worker_ips[count.index]}/${var.network_prefix_length}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.vm_user
      keys     = [trimspace(var.ssh_public_key)]
    }
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    replace_triggered_by = [terraform_data.os_image]
  }
}
