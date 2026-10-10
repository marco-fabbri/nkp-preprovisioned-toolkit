terraform {
  required_version = ">= 1.6.0"
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = ">= 2.6.0, < 3.0.0"
    }
  }
}

provider "vsphere" {
  vsphere_server       = var.vsphere_server
  user                 = var.vsphere_user
  password             = var.vsphere_password
  allow_unverified_ssl = var.vsphere_insecure
}

data "vsphere_datacenter" "target" {
  name = var.vsphere_datacenter
}
data "vsphere_compute_cluster" "target" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.target.id
}
data "vsphere_datastore" "target" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.target.id
}
data "vsphere_network" "target" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.target.id
}

locals {
  sizing    = module.layout.sizing
  cache_dir = "${path.module}/.cache"
  image_url = var.os_distribution == "rocky9" ? var.rocky9_image_url : var.ubuntu24_image_url
  # Named after the URL as well as the OS: a new image URL gives a new OVA and
  # a new local cache entry instead of reusing the old image. The cache path is
  # relative to the module, so the state does not depend on this computer.
  image_id = "${var.os_distribution}-${substr(sha256(local.image_url), 0, 12)}"
  # rhel9_64Guest, not rockylinux_64Guest: the latter needs a virtual hardware
  # newer than vmx-19 (the OVA's), and such VMs do not power on.
  guest_id = var.os_distribution == "rocky9" ? "rhel9_64Guest" : "ubuntu64Guest"
  # Measured on vCenter 8.0U3: vmxnet3 is eth0 on Rocky GenericCloud
  # (net.ifnames=0) and ens192 on Ubuntu.
  guest_nic_name = coalesce(var.guest_nic_name, var.os_distribution == "rocky9" ? "eth0" : "ens192")
  ova_path       = "${local.cache_dir}/nkp-${local.image_id}.ova"
}

resource "terraform_data" "os_image" {
  input = var.os_distribution
}

# The OVA is built on this computer from the distribution cloud image
# (tofu/scripts/build-ova.sh) and imported into a local content library.
resource "terraform_data" "ova" {
  triggers_replace = [var.os_distribution, local.image_url, local.guest_id]
  provisioner "local-exec" {
    command = "img=$(${path.module}/../scripts/fetch-image.sh '${local.image_url}' '${local.cache_dir}' '${local.image_id}') && ${path.module}/../scripts/build-ova.sh \"$img\" 'nkp-${var.os_distribution}' '${local.guest_id}' '${local.ova_path}'"
  }
}

resource "vsphere_content_library" "nkp" {
  name            = var.vsphere_content_library
  storage_backing = [data.vsphere_datastore.target.id]
}

resource "vsphere_content_library_item" "os" {
  name       = "nkp-${local.image_id}"
  library_id = vsphere_content_library.nkp.id
  file_url   = local.ova_path
  depends_on = [terraform_data.ova]
  lifecycle {
    replace_triggered_by = [terraform_data.ova]
  }
}
