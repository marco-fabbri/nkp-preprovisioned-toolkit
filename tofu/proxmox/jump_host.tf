resource "proxmox_virtual_environment_vm" "jump_host" {
  name        = "nkp-jump-host"
  description = format("NKP bastion and CAPI bootstrap host (%s)", local.os_label)
  node_name   = var.proxmox_node
  vm_id       = var.vm_id_base

  # The cloud images do not ship the QEMU guest agent: with it enabled the
  # provider waits 15 minutes for an answer on every refresh and creation.
  agent {
    enabled = false
  }

  cpu {
    cores = local.sizing.jump_host_cores
    type  = "host"
  }

  memory {
    dedicated = local.sizing.jump_host_memory
  }

  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  disk {
    datastore_id = var.datastore_id
    import_from  = local.os_image_id
    interface    = "scsi0"
    size         = local.sizing.jump_host_disk_gb
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
        address = "${var.jump_host_ip}/${var.network_prefix_length}"
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
