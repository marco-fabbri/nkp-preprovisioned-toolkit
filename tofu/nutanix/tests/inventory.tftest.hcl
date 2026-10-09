# The list data sources return objects with many attributes; a mock must set
# them all, so every attribute but ext_id is null.
mock_provider "nutanix" {
  mock_data "nutanix_clusters_v2" {
    defaults = {
      cluster_entities = [{
        backup_eligibility_score = null
        categories               = null
        cluster_profile_ext_id   = null
        config                   = null
        container_name           = null
        expand                   = null
        ext_id                   = "00000000-0000-0000-0000-000000000001"
        inefficient_vm_count     = null
        links                    = null
        name                     = null
        network                  = null
        nodes                    = null
        tenant_id                = null
        upgrade_status           = null
        vm_count                 = null
      }]
    }
  }
  mock_data "nutanix_subnets_v2" {
    defaults = {
      subnets = [{
        bridge_name                      = null
        cluster_name                     = null
        cluster_reference                = null
        description                      = null
        dhcp_options                     = null
        dynamic_ip_addresses             = null
        ext_id                           = "00000000-0000-0000-0000-000000000002"
        hypervisor_type                  = null
        ip_config                        = null
        ip_prefix                        = null
        ip_usage                         = null
        is_advanced_networking           = null
        is_connected                     = null
        is_external                      = null
        is_nat_enabled                   = null
        links                            = null
        metadata                         = null
        migration_state                  = null
        name                             = null
        network_function_chain_reference = null
        network_id                       = null
        project_ext_id                   = null
        reserved_ip_addresses            = null
        shared_with_projects             = null
        subnet_type                      = null
        virtual_switch                   = null
        virtual_switch_reference         = null
        vpc                              = null
        vpc_reference                    = null
      }]
    }
  }
}

variables {
  nutanix_endpoint     = "10.10.10.5"
  nutanix_username     = "admin"
  nutanix_password     = "secret"
  nutanix_cluster_name = "cluster01"
  nutanix_subnet_name  = "vlan10"
  # Set explicitly: tofu test also reads a local terraform.tfvars, and the
  # results must not depend on one.
  nutanix_subnet_ipam            = false
  nutanix_storage_container_name = ""
  nutanix_insecure               = false
  os_distribution                = "ubuntu24"
  network_prefix_length          = 24
  dns_servers                    = ["10.10.10.1"]
  guest_nic_name                 = null
  sizing_profile                 = "contract-test"
  ssh_public_key                 = "ssh-ed25519 AAAAexample user@laptop"
  network_gateway                = "10.10.10.1"
  jump_host_ip                   = "10.10.10.80"
  control_plane_ips              = ["10.10.10.81"]
  control_plane_vip              = "10.10.10.85"
  worker_ips                     = ["10.10.10.86"]
}

# Values measured on AHV (PC 7.6): the virtio NIC is eth0 on Rocky
# GenericCloud (net.ifnames=0) and ens3 on Ubuntu; the SCSI disks are
# pci-0000:00:04.0-scsi-0:0:<index>:0 on both.
run "inventory_uses_the_measured_ahv_names_on_ubuntu" {
  command = plan
  assert {
    condition     = strcontains(output.ansible_inventory, "virtual_ip_interface = ens3\n") && strcontains(output.ansible_inventory, "ceph_osd_device = /dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:1:0\n")
    error_message = "Ubuntu on AHV: ens3 and the SCSI slot 1 path"
  }
  assert {
    condition     = strcontains(output.ansible_inventory, "\"/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:2:0\",\"/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:3:0\",\"/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:4:0\",\"/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:5:0\"")
    error_message = "local volumes must be SCSI slots 2 to 5"
  }
}

run "inventory_uses_eth0_on_rocky" {
  command = plan
  variables {
    os_distribution = "rocky9"
  }
  assert {
    condition     = strcontains(output.ansible_inventory, "virtual_ip_interface = eth0\n")
    error_message = "Rocky GenericCloud on AHV names the NIC eth0"
  }
}

run "guest_nic_name_overrides_the_default" {
  command = plan
  variables {
    guest_nic_name = "ens5"
  }
  assert {
    condition     = strcontains(output.ansible_inventory, "virtual_ip_interface = ens5\n")
    error_message = "guest_nic_name must override the measured default"
  }
}

run "worker_has_six_disks" {
  command = plan
  assert {
    condition     = length(nutanix_virtual_machine_v2.worker[0].disks) == 6 && length(nutanix_virtual_machine_v2.jump_host.disks) == 1
    error_message = "worker must have OS + Ceph + 4 volumes, jump host OS only"
  }
}

run "ipam_reserves_the_static_address" {
  command = plan
  variables {
    nutanix_subnet_ipam = true
  }
  assert {
    condition     = nutanix_virtual_machine_v2.worker[0].nics[0].nic_network_info[0].virtual_ethernet_nic_network_info[0].ipv4_config[0].ip_address[0].value == "10.10.10.86"
    error_message = "with IPAM the worker NIC must reserve its static address on AHV"
  }
  # The managed subnet owns the prefix: AHV rejects a reservation carrying one
  # ("invalid argument with key 'IP Address Prefix Length'").
  assert {
    condition     = nutanix_virtual_machine_v2.worker[0].nics[0].nic_network_info[0].virtual_ethernet_nic_network_info[0].ipv4_config[0].ip_address[0].prefix_length == null
    error_message = "the IPAM reservation must not set a prefix length"
  }
}

run "no_ipam_leaves_the_address_to_cloud_init" {
  command = plan
  assert {
    condition     = length(nutanix_virtual_machine_v2.jump_host.nics[0].nic_network_info[0].virtual_ethernet_nic_network_info[0].ipv4_config) == 0
    error_message = "without IPAM no address is reserved on AHV"
  }
}

# Provider 2.5 maps only "CONFIG_DRIVE_V2"; any other value (such as the API
# name CONFIG_DRIVE) makes the plugin panic when the VM is created.
run "cloud_init_datasource_is_config_drive_v2" {
  command = plan
  assert {
    condition     = nutanix_virtual_machine_v2.worker[0].guest_customization[0].config[0].cloud_init[0].datasource_type == "CONFIG_DRIVE_V2" && nutanix_virtual_machine_v2.jump_host.guest_customization[0].config[0].cloud_init[0].datasource_type == "CONFIG_DRIVE_V2" && nutanix_virtual_machine_v2.control_plane[0].guest_customization[0].config[0].cloud_init[0].datasource_type == "CONFIG_DRIVE_V2"
    error_message = "datasource_type must be CONFIG_DRIVE_V2 on every VM"
  }
}

# Prism Central does not return the cloud-init payload, so a change to it is
# invisible to the provider: each VM is tied to a hash of its payload and is
# rebuilt when it changes (a corrected address, gateway, DNS or key).
run "cloud_init_change_rebuilds_the_vm" {
  command = plan
  assert {
    condition     = terraform_data.worker_cloud_init[0].input == sha256(base64decode(nutanix_virtual_machine_v2.worker[0].guest_customization[0].config[0].cloud_init[0].cloud_init_script[0].user_data[0].value)) && terraform_data.jump_host_cloud_init.input == sha256(base64decode(nutanix_virtual_machine_v2.jump_host.guest_customization[0].config[0].cloud_init[0].cloud_init_script[0].user_data[0].value)) && terraform_data.control_plane_cloud_init[0].input == sha256(base64decode(nutanix_virtual_machine_v2.control_plane[0].guest_customization[0].config[0].cloud_init[0].cloud_init_script[0].user_data[0].value))
    error_message = "every VM needs a terraform_data holding the hash of its cloud-init payload"
  }
}
