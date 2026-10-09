# Everything a VM is made of, per VM. triggers_replace hashes it: any change
# (OS, size, cloud-init, hardware) rebuilds the VM, since there is no in-place
# update path without the ESXi API. The SSH target and the owner token are
# kept out of the hash: reaching the host by another address or port must not
# rebuild (and wipe) the VMs.
locals {
  vm_definitions = { for name, v in local.vms : name => {
    name           = name
    vm_dir         = "${local.base_dir}/${name}"
    base_vmdk      = local.base_vmdk
    os_gb          = tostring(v.os_gb)
    data_gb        = join(" ", [for g in v.data_gb : tostring(g)])
    user_data      = module.layout.cloud_init[name].user_data
    meta_data      = module.layout.cloud_init[name].meta_data
    network_config = module.layout.cloud_init[name].network_config
    vmx = templatefile("${path.module}/vmx.tftpl", {
      hw_version = var.esxi_virtual_hw_version
      name       = name
      annotation = "NKP pre-provisioned node (${module.layout.os_label})"
      guest_os   = local.guest_os
      cpus       = v.cpus
      memory     = v.memory
      port_group = var.esxi_port_group
      disks      = concat(["os.vmdk"], [for i, _ in v.data_gb : "data${i + 1}.vmdk"])
    })
  } }
}

resource "terraform_data" "vm" {
  for_each         = local.vm_definitions
  input            = merge(each.value, { ssh = local.ssh_target, owner = terraform_data.owner.output })
  triggers_replace = [terraform_data.os_image.output, terraform_data.base_disk.id, sha256(jsonencode(each.value))]

  provisioner "local-exec" {
    command = "${path.module}/scripts/esxi-vm.sh create"
    environment = {
      ESXI_HOST          = self.input.ssh.host
      ESXI_USER          = self.input.ssh.user
      ESXI_PORT          = self.input.ssh.port
      NAME               = self.input.name
      OWNER              = self.input.owner
      VM_DIR             = self.input.vm_dir
      BASE_VMDK          = self.input.base_vmdk
      OS_GB              = self.input.os_gb
      DATA_GB            = self.input.data_gb
      VMX_B64            = base64encode(self.input.vmx)
      USER_DATA_B64      = base64encode(self.input.user_data)
      META_DATA_B64      = base64encode(self.input.meta_data)
      NETWORK_CONFIG_B64 = base64encode(self.input.network_config)
      SCRIPTS            = abspath("${path.module}/../scripts")
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/esxi-vm.sh destroy"
    environment = {
      ESXI_HOST = self.input.ssh.host
      ESXI_USER = self.input.ssh.user
      ESXI_PORT = self.input.ssh.port
      NAME      = self.input.name
      OWNER     = self.input.owner
      VM_DIR    = self.input.vm_dir
    }
  }
}
