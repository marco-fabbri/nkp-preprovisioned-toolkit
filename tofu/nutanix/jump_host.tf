# Prism Central does not return the cloud-init payload (ignore_changes on
# guest_customization below): this hash makes a change to it, such as a
# corrected address or key, rebuild the VM.
resource "terraform_data" "jump_host_cloud_init" {
  input = sha256(module.layout.user_data_with_network[module.layout.jump_host_name])
}

resource "nutanix_virtual_machine_v2" "jump_host" {
  name                 = module.layout.jump_host_name
  description          = format("NKP bastion and CAPI bootstrap host (%s)", module.layout.os_label)
  num_sockets          = local.sizing.jump_host_cores
  num_cores_per_socket = 1
  memory_size_bytes    = local.sizing.jump_host_memory * 1024 * 1024
  power_state          = "ON"

  cluster {
    ext_id = local.cluster_ext_id
  }

  # OS disk only, cloned from the image and grown to the profile size.
  disks {
    disk_address {
      bus_type = "SCSI"
      index    = 0
    }
    backing_info {
      vm_disk {
        disk_size_bytes = local.sizing.jump_host_disk_gb * local.gib
        data_source {
          reference {
            image_reference {
              image_ext_id = local.image_ext_id
            }
          }
        }
      }
    }
  }

  nics {
    nic_network_info {
      virtual_ethernet_nic_network_info {
        nic_type  = "NORMAL_NIC"
        vlan_mode = "ACCESS"
        subnet {
          ext_id = local.subnet_ext_id
        }
        # On a subnet with AHV IPAM the static address is also reserved on AHV,
        # so that its DHCP pool never hands it to another VM.
        dynamic "ipv4_config" {
          for_each = var.nutanix_subnet_ipam ? [var.jump_host_ip] : []
          content {
            should_assign_ip = true
            # No prefix length: the managed subnet owns it, and AHV rejects
            # a reservation that carries one.
            ip_address {
              value = ipv4_config.value
            }
          }
        }
      }
    }
  }

  boot_config {
    legacy_boot {
      boot_order = ["DISK", "CDROM", "NETWORK"]
    }
  }

  # ConfigDrive has no network document: the static address is written by
  # user-data (module "layout", user_data_with_network).
  guest_customization {
    config {
      cloud_init {
        datasource_type = "CONFIG_DRIVE_V2"
        cloud_init_script {
          user_data {
            value = base64encode(module.layout.user_data_with_network[module.layout.jump_host_name])
          }
        }
      }
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.os_image, terraform_data.jump_host_cloud_init]
    # Prism Central does not return the cloud-init payload after creation,
    # attaches the ConfigDrive that carries it as a CD-ROM of its own, and
    # reports should_assign_ip = false once an IPAM address is assigned (the
    # flag is a creation-time request).
    ignore_changes = [
      guest_customization,
      cd_roms,
      nics[0].nic_network_info[0].virtual_ethernet_nic_network_info[0].ipv4_config[0].should_assign_ip,
    ]
  }
}
