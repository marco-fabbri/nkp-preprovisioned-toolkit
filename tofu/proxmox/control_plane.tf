resource "proxmox_virtual_environment_vm" "control_plane" {
  count       = length(var.control_plane_ips)
  name        = format("nkp-cp-%02d", count.index + 1)
  description = format("NKP pre-provisioned control plane node %02d (%s)", count.index + 1, local.os_label)
  node_name   = var.proxmox_node
  vm_id       = var.vm_id_base + 1 + count.index

  # The cloud images do not ship the QEMU guest agent: with it enabled the
  # provider waits 15 minutes for an answer on every refresh and creation.
  agent {
    enabled = false
  }

  cpu {
    cores = local.sizing.control_plane_cores
    type  = "host"
  }

  memory {
    dedicated = local.sizing.control_plane_memory
  }

  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  disk {
    datastore_id = var.datastore_id
    import_from  = local.os_image_id
    interface    = "scsi0"
    size         = local.sizing.os_disk_gb
    discard      = "on"
    ssd          = true
    iothread     = true
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
        address = "${var.control_plane_ips[count.index]}/${var.network_prefix_length}"
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
