# No provider to mock: the module drives the host over SSH from terraform_data
# provisioners, which a plan never runs.

variables {
  esxi_host         = "10.10.10.4"
  esxi_ssh_user     = "root"
  esxi_ssh_port     = 22
  esxi_datastore    = "datastore1"
  esxi_port_group   = "VM Network"
  esxi_folder       = "nkp"
  os_distribution   = "ubuntu24"
  sizing_profile    = "contract-test"
  ssh_public_key    = "ssh-ed25519 AAAAexample user@laptop"
  network_gateway   = "10.10.10.1"
  dns_servers       = ["10.10.10.1"]
  jump_host_ip      = "10.10.10.80"
  control_plane_ips = ["10.10.10.81"]
  control_plane_vip = "10.10.10.85"
  worker_ips        = ["10.10.10.86"]
  # Set explicitly: tofu test also reads a local terraform.tfvars.
  guest_nic_name     = null
  ubuntu24_image_url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  rocky9_image_url   = "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
}

# Values measured on ESXi 8.0U3e (free licence): vmxnet3 is ens192 on Ubuntu
# and eth0 on Rocky GenericCloud (net.ifnames=0); the PVSCSI disks are
# pci-0000:03:00.0-scsi-0:0:<unit>:0 on both.
run "inventory_uses_the_measured_esxi_names_on_ubuntu" {
  command = plan
  assert {
    condition     = strcontains(output.ansible_inventory, "virtual_ip_interface = ens192\n") && strcontains(output.ansible_inventory, "ceph_osd_device = /dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:1:0\n")
    error_message = "Ubuntu on ESXi: ens192 and the SCSI unit 1 path"
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
    condition     = strcontains(output.ansible_inventory, "virtual_ip_interface = eth0\n") && strcontains(terraform_data.vm["nkp-worker-01"].input.vmx, "guestOS = \"rhel9-64\"")
    error_message = "Rocky on ESXi: eth0 and the rhel9-64 guest type"
  }
}

run "vmx_layout" {
  command = plan
  assert {
    condition     = length(terraform_data.vm) == 3 && strcontains(terraform_data.vm["nkp-worker-01"].input.vmx, "scsi0:5.fileName = \"data5.vmdk\"") && !strcontains(terraform_data.vm["nkp-jump-host"].input.vmx, "scsi0:1.")
    error_message = "worker: 6 disks; jump host: OS disk only"
  }
  assert {
    condition     = strcontains(terraform_data.vm["nkp-worker-01"].input.vmx, "scsi0.virtualDev = \"pvscsi\"") && strcontains(terraform_data.vm["nkp-worker-01"].input.vmx, "ethernet0.virtualDev = \"vmxnet3\"") && strcontains(terraform_data.vm["nkp-worker-01"].input.vmx, "ethernet0.networkName = \"VM Network\"")
    error_message = "PVSCSI, vmxnet3 and the port group are part of the contract"
  }
  assert {
    condition     = terraform_data.vm["nkp-worker-01"].input.data_gb == "5 5 5 5 5" && terraform_data.vm["nkp-jump-host"].input.data_gb == "" && terraform_data.vm["nkp-worker-01"].input.os_gb == "20"
    error_message = "contract-test disk sizes"
  }
}

run "vm_folders_and_base_disk_per_os" {
  command = plan
  assert {
    condition     = terraform_data.vm["nkp-cp-01"].input.vm_dir == "/vmfs/volumes/datastore1/nkp/nkp-cp-01" && startswith(terraform_data.vm["nkp-cp-01"].input.base_vmdk, "/vmfs/volumes/datastore1/nkp/images/ubuntu24-")
    error_message = "each VM lives in its own folder under esxi_folder; the base disk is per OS"
  }
}

run "network_config_uses_the_guest_nic" {
  command = plan
  assert {
    condition     = yamldecode(terraform_data.vm["nkp-worker-01"].input.network_config).ethernets["ens192"].addresses[0] == "10.10.10.86/24"
    error_message = "the NoCloud network config must address the guest NIC"
  }
}

# The SSH target is not part of what rebuilds a VM: moving from an IP to an
# FQDN or to another port must not recreate (and wipe) every VM.
run "ssh_target_is_kept_out_of_the_vm_definition" {
  command = plan
  assert {
    condition     = terraform_data.vm["nkp-worker-01"].input.ssh.host == "10.10.10.4" && !contains(keys(terraform_data.vm["nkp-worker-01"].input), "host") && !contains(keys(terraform_data.vm["nkp-worker-01"].input), "port")
    error_message = "host, user and port belong to input.ssh, outside the hashed VM definition"
  }
}

# Every VM carries the owner token of this state, so the scripts never touch a
# same-named VM of another lab on the same host.
run "vms_carry_the_owner_token" {
  command = plan
  assert {
    condition     = contains(keys(terraform_data.vm["nkp-cp-01"].input), "owner") && contains(keys(terraform_data.vm["nkp-worker-01"].input), "owner")
    error_message = "the VMs must carry the owner token of this state"
  }
}

# The base disk and the local cache are named after the image URL: a new URL
# gives a new image instead of silently reusing the cached one.
run "base_disk_is_named_after_the_image_url" {
  command = plan
  variables {
    ubuntu24_image_url = "https://example.com/noble-20260101.img"
  }
  assert {
    condition     = terraform_data.vm["nkp-cp-01"].input.base_vmdk == "/vmfs/volumes/datastore1/nkp/images/ubuntu24-${substr(sha256("https://example.com/noble-20260101.img"), 0, 12)}.vmdk"
    error_message = "the base disk name must carry a hash of the image URL"
  }
}

run "rejects_a_folder_outside_the_datastore" {
  command = plan
  variables {
    esxi_folder = "../.."
  }
  expect_failures = [var.esxi_folder]
}

run "rejects_a_quote_in_the_datastore_name" {
  command = plan
  variables {
    esxi_datastore = "data'store"
  }
  expect_failures = [var.esxi_datastore]
}

run "rejects_a_dot_datastore" {
  command = plan
  variables {
    esxi_datastore = "."
  }
  expect_failures = [var.esxi_datastore]
}

run "rejects_a_dotdot_datastore" {
  command = plan
  variables {
    esxi_datastore = ".."
  }
  expect_failures = [var.esxi_datastore]
}

run "accepts_a_datastore_name_with_spaces" {
  command = plan
  variables {
    esxi_datastore = "datastore1 (1)"
  }
  assert {
    condition     = terraform_data.vm["nkp-cp-01"].input.vm_dir == "/vmfs/volumes/datastore1 (1)/nkp/nkp-cp-01"
    error_message = "a datastore name with spaces must be accepted"
  }
}
