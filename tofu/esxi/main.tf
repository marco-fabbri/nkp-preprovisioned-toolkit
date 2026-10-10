terraform {
  required_version = ">= 1.6.0"
}

# No provider: the free ESXi licence blocks the write API and ovftool, so the
# module drives the host over SSH (vmkfstools, vim-cmd) from terraform_data
# provisioners. Authentication is the operator's SSH agent; no password is
# stored in the module.
locals {
  sizing    = module.layout.sizing
  base_dir  = "/vmfs/volumes/${var.esxi_datastore}/${var.esxi_folder}"
  image_url = var.os_distribution == "rocky9" ? var.rocky9_image_url : var.ubuntu24_image_url
  # Named after the URL as well as the OS: a new image URL gives a new base
  # disk and a new local cache entry instead of reusing the old image.
  image_id  = "${var.os_distribution}-${substr(sha256(local.image_url), 0, 12)}"
  base_vmdk = "${local.base_dir}/images/${local.image_id}.vmdk"
  guest_os  = var.os_distribution == "rocky9" ? "rhel9-64" : "ubuntu-64"
  # Measured on ESXi 8: vmxnet3 is eth0 on Rocky GenericCloud (net.ifnames=0)
  # and ens192 on Ubuntu.
  guest_nic_name = coalesce(var.guest_nic_name, var.os_distribution == "rocky9" ? "eth0" : "ens192")
  cache_dir      = abspath("${path.module}/.cache")
  ssh_target     = { host = var.esxi_host, user = var.esxi_ssh_user, port = tostring(var.esxi_ssh_port) }
  vms = merge(
    { (module.layout.jump_host_name) = { cpus = local.sizing.jump_host_cores, memory = local.sizing.jump_host_memory, os_gb = local.sizing.jump_host_disk_gb, data_gb = [] } },
    { for n in module.layout.control_plane_names : n => { cpus = local.sizing.control_plane_cores, memory = local.sizing.control_plane_memory, os_gb = local.sizing.os_disk_gb, data_gb = [] } },
    { for n in module.layout.worker_names : n => { cpus = local.sizing.worker_cores, memory = local.sizing.worker_memory, os_gb = local.sizing.os_disk_gb,
    data_gb = concat([local.sizing.ceph_disk_gb], [for i in range(module.layout.local_volume_count) : local.sizing.local_volume_gb]) } },
  )
}

resource "terraform_data" "os_image" {
  input = var.os_distribution
}

# Owner token of this state, written into every VM folder: the scripts only
# ever delete a folder that carries it, so a same-named VM of another lab on
# the same host is never touched. Generated once, then kept.
resource "terraform_data" "owner" {
  input = replace(uuid(), "-", "")
  lifecycle {
    ignore_changes = [input]
  }
}

# The cloud image converted to an ESXi thin disk once per OS; every VM gets a
# copy of it.
resource "terraform_data" "base_disk" {
  triggers_replace = [var.os_distribution, local.image_url, var.esxi_datastore, var.esxi_folder]
  input            = merge(local.ssh_target, { base_vmdk = local.base_vmdk, url = local.image_url, os = local.image_id, cache = local.cache_dir })

  provisioner "local-exec" {
    command = "${path.module}/scripts/esxi-image.sh create"
    environment = {
      ESXI_HOST = self.input.host, ESXI_USER = self.input.user, ESXI_PORT = self.input.port
      BASE_VMDK = self.input.base_vmdk, IMAGE_URL = self.input.url, OS = self.input.os, CACHE_DIR = self.input.cache
      SCRIPTS   = abspath("${path.module}/../scripts")
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/esxi-image.sh destroy"
    environment = {
      ESXI_HOST = self.input.host, ESXI_USER = self.input.user, ESXI_PORT = self.input.port, BASE_VMDK = self.input.base_vmdk
    }
  }
}
