mock_provider "vsphere" {
  mock_data "vsphere_datacenter" {
    defaults = { id = "datacenter-1" }
  }
  mock_data "vsphere_compute_cluster" {
    defaults = { id = "domain-c1", resource_pool_id = "resgroup-1" }
  }
  mock_data "vsphere_datastore" {
    defaults = { id = "datastore-1" }
  }
  mock_data "vsphere_network" {
    defaults = { id = "network-1" }
  }
}

variables {
  vsphere_server     = "vcenter.example.com"
  vsphere_user       = "administrator@vsphere.local"
  vsphere_password   = "secret"
  vsphere_insecure   = false
  vsphere_datacenter = "dc1"
  vsphere_cluster    = "cluster1"
  vsphere_datastore  = "datastore1"
  vsphere_network    = "VM Network"
  vsphere_folder     = ""
  os_distribution    = "ubuntu24"
  sizing_profile     = "contract-test"
  ssh_public_key     = "ssh-ed25519 AAAAexample user@laptop"
  network_gateway    = "10.10.10.1"
  dns_servers        = ["10.10.10.1"]
  jump_host_ip       = "10.10.10.80"
  control_plane_ips  = ["10.10.10.81"]
  control_plane_vip  = "10.10.10.85"
  worker_ips         = ["10.10.10.86"]
  ubuntu24_image_url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  # Set explicitly: tofu test also reads a local terraform.tfvars.
  guest_nic_name = null
}

# Values measured on vCenter 8.0U3 (nested ESXi 8.0U3): vmxnet3 is ens192 on
# Ubuntu and eth0 on Rocky GenericCloud (net.ifnames=0); the PVSCSI disks are
# pci-0000:03:00.0-scsi-0:0:<unit>:0, as on a standalone ESXi.
run "inventory_uses_the_measured_vsphere_names_on_ubuntu" {
  command = plan
  assert {
    condition     = strcontains(output.ansible_inventory, "virtual_ip_interface = ens192\n") && strcontains(output.ansible_inventory, "ceph_osd_device = /dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:1:0\n")
    error_message = "Ubuntu on vSphere: ens192 and the SCSI unit 1 path"
  }
  assert {
    condition     = strcontains(output.ansible_inventory, "\"/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:2:0\",\"/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:3:0\",\"/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:4:0\",\"/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:5:0\"")
    error_message = "local volumes must be SCSI units 2 to 5"
  }
}

run "rocky_uses_eth0" {
  command = plan
  variables {
    os_distribution = "rocky9"
  }
  assert {
    condition     = strcontains(output.ansible_inventory, "virtual_ip_interface = eth0\n")
    error_message = "Rocky GenericCloud on vSphere names the NIC eth0"
  }
  # rockylinux_64Guest needs a newer virtual hardware than vmx-19 and the VMs
  # do not power on ("No host is compatible with the virtual machine").
  assert {
    condition     = vsphere_virtual_machine.worker[0].guest_id == "rhel9_64Guest"
    error_message = "Rocky VMs must be declared as rhel9_64Guest"
  }
}

run "worker_disk_layout" {
  command = plan
  assert {
    condition     = [for d in vsphere_virtual_machine.worker[0].disk : d.unit_number] == [0, 1, 2, 3, 4, 5] && length(vsphere_virtual_machine.jump_host.disk) == 1
    error_message = "worker: OS + Ceph + 4 volumes on units 0..5; jump host: OS only"
  }
  assert {
    condition     = vsphere_virtual_machine.worker[0].disk[1].size == 5 && vsphere_virtual_machine.worker[0].disk[5].size == 5 && vsphere_virtual_machine.worker[0].disk[0].size == 20
    error_message = "contract-test disk sizes"
  }
}

run "controller_and_disk_uuid" {
  command = plan
  assert {
    condition     = vsphere_virtual_machine.worker[0].scsi_type == "pvscsi" && vsphere_virtual_machine.worker[0].enable_disk_uuid == true && vsphere_virtual_machine.worker[0].network_interface[0].adapter_type == "vmxnet3"
    error_message = "PVSCSI, disk.EnableUUID and vmxnet3 are part of the contract"
  }
}

run "each_vm_mounts_its_own_cidata" {
  command = plan
  assert {
    condition     = startswith(vsphere_file.cidata["nkp-worker-01"].destination_file, "nkp-cidata/nkp-worker-01-") && vsphere_file.cidata["nkp-worker-01"].destination_file != vsphere_file.cidata["nkp-cp-01"].destination_file
    error_message = "every VM needs its own cidata ISO on the datastore"
  }
}

# The OVA is named after the image URL: a new URL gives a new image instead of
# silently reusing the cached one.
run "ova_is_named_after_the_image_url" {
  command = plan
  variables {
    ubuntu24_image_url = "https://example.com/noble-20260101.img"
  }
  assert {
    condition     = strcontains(vsphere_content_library_item.os.file_url, "nkp-ubuntu24-${substr(sha256("https://example.com/noble-20260101.img"), 0, 12)}.ova")
    error_message = "the OVA name must carry a hash of the image URL"
  }
  assert {
    condition     = vsphere_content_library_item.os.name == "nkp-ubuntu24-${substr(sha256("https://example.com/noble-20260101.img"), 0, 12)}"
    error_message = "the library item must carry the hash too: a new image never collides with the item it replaces"
  }
}

# The cidata ISOs are read from a path relative to the module, so running
# OpenTofu from another checkout does not re-upload every ISO.
run "cidata_source_path_is_relative" {
  command = plan
  assert {
    condition     = !startswith(vsphere_file.cidata["nkp-worker-01"].source_file, "/")
    error_message = "source_file must not be an absolute path of this computer"
  }
}

# A cloud-init change gives a new ISO; the VM is tied to a hash of its
# documents and is rebuilt (cloud-init only reads the seed of a new instance).
run "cloud_init_change_rebuilds_the_vm" {
  command = plan
  assert {
    condition     = strcontains(vsphere_file.cidata["nkp-worker-01"].destination_file, substr(terraform_data.worker_cloud_init[0].input, 0, 12)) && strcontains(vsphere_file.cidata["nkp-jump-host"].destination_file, substr(terraform_data.jump_host_cloud_init.input, 0, 12)) && strcontains(vsphere_file.cidata["nkp-cp-01"].destination_file, substr(terraform_data.control_plane_cloud_init[0].input, 0, 12))
    error_message = "every VM needs a terraform_data holding the hash of the cidata ISO it mounts"
  }
}
