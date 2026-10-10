terraform {
  required_version = ">= 1.6.0"
  required_providers {
    # The v2 resources use the v4 APIs of Prism Central (pc.2024.3 or later);
    # 2.5.0 is the validated release (2.2.0 lacks nic_network_info).
    nutanix = {
      source  = "nutanix/nutanix"
      version = ">= 2.5.0, < 3.0.0"
    }
  }
}

provider "nutanix" {
  endpoint = var.nutanix_endpoint
  port     = var.nutanix_port
  username = var.nutanix_username
  password = var.nutanix_password
  insecure = var.nutanix_insecure
}

data "nutanix_clusters_v2" "target" {
  filter = "name eq '${var.nutanix_cluster_name}'"
}

data "nutanix_subnets_v2" "target" {
  filter = "name eq '${var.nutanix_subnet_name}'"
}

data "nutanix_storage_containers_v2" "target" {
  count  = var.nutanix_storage_container_name == "" ? 0 : 1
  filter = "name eq '${var.nutanix_storage_container_name}'"
}

locals {
  gib                  = 1024 * 1024 * 1024
  sizing               = module.layout.sizing
  cluster_ext_id       = one(data.nutanix_clusters_v2.target.cluster_entities).ext_id
  subnet_ext_id        = one(data.nutanix_subnets_v2.target.subnets).ext_id
  storage_container_id = var.nutanix_storage_container_name == "" ? null : one(data.nutanix_storage_containers_v2.target[0].storage_containers).container_ext_id
  image_ext_id         = var.os_distribution == "rocky9" ? nutanix_images_v2.rocky9.id : nutanix_images_v2.ubuntu24.id
  guest_nic_name       = coalesce(var.guest_nic_name, var.os_distribution == "rocky9" ? "eth0" : "ens3")
  data_disk_gb         = concat([local.sizing.ceph_disk_gb], [for i in range(module.layout.local_volume_count) : local.sizing.local_volume_gb])
}

# Changing the operating system must rebuild the virtual machines.
resource "terraform_data" "os_image" {
  input = var.os_distribution
}

resource "nutanix_images_v2" "rocky9" {
  name                     = "nkp-rocky9-genericcloud"
  type                     = "DISK_IMAGE"
  cluster_location_ext_ids = [local.cluster_ext_id]
  source {
    url_source {
      url = var.rocky9_image_url
    }
  }
}

resource "nutanix_images_v2" "ubuntu24" {
  name                     = "nkp-ubuntu24-cloudimg"
  type                     = "DISK_IMAGE"
  cluster_location_ext_ids = [local.cluster_ext_id]
  source {
    url_source {
      url = var.ubuntu24_image_url
    }
  }
}
