terraform {
  required_version = ">= 1.6.0"
  required_providers {
    # 0.100.0 is the first release with the short resource names
    # (proxmox_download_file) and the import_from disk attribute.
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.100.0, < 1.0.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  api_token = var.proxmox_api_token != "" ? var.proxmox_api_token : null
  username  = var.proxmox_username != "" ? var.proxmox_username : null
  password  = var.proxmox_password != "" ? var.proxmox_password : null

  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}

# Sizes, names and the inventory come from the shared layout module
# (layout.tf); these aliases keep the VM resources unchanged.
locals {
  sizing             = module.layout.sizing
  ceph_disk_gb       = module.layout.sizing.ceph_disk_gb
  local_volume_gb    = module.layout.sizing.local_volume_gb
  local_volume_count = module.layout.local_volume_count
  os_label           = module.layout.os_label
  os_image_id        = var.template_file_id != "" ? var.template_file_id : (var.os_distribution == "rocky9" ? proxmox_download_file.rocky9.id : proxmox_download_file.ubuntu24.id)
}

# Changing the operating system must rebuild the virtual machines: the provider
# would otherwise only update them in place and keep the old system disk.
resource "terraform_data" "os_image" {
  input = var.os_distribution
}

resource "proxmox_download_file" "rocky9" {
  node_name    = var.proxmox_node
  datastore_id = var.image_datastore
  content_type = "import"
  url          = var.rocky9_image_url
  file_name    = "Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
}

resource "proxmox_download_file" "ubuntu24" {
  node_name    = var.proxmox_node
  datastore_id = var.image_datastore
  content_type = "import"
  url          = var.ubuntu24_image_url
  file_name    = "noble-server-cloudimg-amd64.qcow2"
}
