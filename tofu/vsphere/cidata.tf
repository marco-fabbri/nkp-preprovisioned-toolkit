# One NoCloud ISO per VM, named after its content so that a change uploads a
# new file instead of silently keeping the old one on the datastore.
locals {
  cidata = { for name, ci in module.layout.cloud_init : name => merge(ci, {
    file = "${name}-${substr(sha256(join("", [ci.user_data, ci.meta_data, ci.network_config])), 0, 12)}.iso"
  }) }
}

resource "terraform_data" "cidata_iso" {
  for_each         = local.cidata
  triggers_replace = [each.value.file]
  provisioner "local-exec" {
    command     = "d='${local.cache_dir}/cidata/${each.key}' && mkdir -p \"$d\" && printf '%s' \"$UD\" > \"$d/user-data\" && printf '%s' \"$MD\" > \"$d/meta-data\" && printf '%s' \"$NC\" > \"$d/network-config\" && ${path.module}/../scripts/make-cidata-iso.sh \"$d\" '${local.cache_dir}/${each.value.file}'"
    environment = { UD = each.value.user_data, MD = each.value.meta_data, NC = each.value.network_config }
  }
}

resource "vsphere_file" "cidata" {
  for_each           = local.cidata
  datacenter         = var.vsphere_datacenter
  datastore          = var.vsphere_datastore
  source_file        = "${local.cache_dir}/${each.value.file}"
  destination_file   = "nkp-cidata/${each.value.file}"
  create_directories = true
  depends_on         = [terraform_data.cidata_iso]
}
