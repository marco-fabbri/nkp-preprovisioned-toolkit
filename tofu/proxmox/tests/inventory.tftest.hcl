# The inventory snippet is part of the contract: this test pins its text, so a
# refactoring that changes a single character of it fails here.
# The mocked download needs a real-looking file id: the VM disk validates it.
mock_provider "proxmox" {
  mock_resource "proxmox_download_file" {
    defaults = {
      id = "local:import/mock.qcow2"
    }
  }
}

variables {
  proxmox_endpoint  = "https://10.10.10.2:8006/"
  proxmox_api_token = "terraform@pve!tofu=11111111-2222-3333-4444-555555555555"
  os_distribution   = "rocky9"
  sizing_profile    = "pro-ultimate"
  ssh_public_key    = "ssh-ed25519 AAAAexample user@laptop"
  network_gateway   = "10.10.10.1"
  dns_servers       = ["10.10.10.1", "1.1.1.1"]
  jump_host_ip      = "10.10.10.80"
  control_plane_ips = ["10.10.10.81", "10.10.10.82", "10.10.10.83"]
  control_plane_vip = "10.10.10.85"
  worker_ips        = ["10.10.10.86", "10.10.10.87", "10.10.10.88", "10.10.10.89"]
}

run "inventory_unchanged" {
  command = plan
  assert {
    condition     = output.ansible_inventory == file("${path.module}/tests/inventory.golden")
    error_message = "The Proxmox inventory snippet changed"
  }
}

run "contract_test_inventory_unchanged" {
  command = plan
  variables {
    sizing_profile    = "contract-test"
    os_distribution   = "ubuntu24"
    control_plane_ips = ["10.10.10.81"]
    worker_ips        = ["10.10.10.86"]
  }
  assert {
    condition     = output.ansible_inventory == file("${path.module}/tests/inventory-contract.golden")
    error_message = "The Proxmox contract-test inventory snippet changed"
  }
}
