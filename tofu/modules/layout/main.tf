# Provider independent layout: sizes, names, cloud-init documents and the
# inventory snippet. No resources and no providers.

# pro-ultimate follows the general resource requirements that the NKP 2.18
# guide sets for Pro and Ultimate clusters, the licences pre-provisioned
# infrastructure requires. The local volume disks get 110 GB because
# Prometheus claims exactly 100 GiB and the file system is a little smaller
# than the disk. contract-test is far below the NKP minimums: it only exists to
# exercise a provider module with ./deploy.sh tofu-verify.
locals {
  vm_sizes = {
    "pro-ultimate" = {
      control_plane_cores  = 4
      control_plane_memory = 16384
      worker_cores         = 8
      worker_memory        = 32768
      jump_host_cores      = 4
      jump_host_memory     = 8192
      os_disk_gb           = 80
      jump_host_disk_gb    = 50
      ceph_disk_gb         = 50
      local_volume_gb      = 110
    }
    "contract-test" = {
      control_plane_cores  = 2
      control_plane_memory = 2048
      worker_cores         = 2
      worker_memory        = 2048
      jump_host_cores      = 2
      jump_host_memory     = 2048
      os_disk_gb           = 20
      jump_host_disk_gb    = 20
      ceph_disk_gb         = 5
      local_volume_gb      = 5
    }
  }
  profile = local.vm_sizes[var.sizing_profile]
  sizing = merge(local.profile, {
    ceph_disk_gb    = coalesce(var.ceph_disk_size_gb, local.profile.ceph_disk_gb)
    local_volume_gb = coalesce(var.local_volume_size_gb, local.profile.local_volume_gb)
  })
  local_volume_count = 4

  os_family = var.os_distribution == "rocky9" ? "rocky" : "ubuntu"
  os_label  = var.os_distribution == "rocky9" ? "Rocky Linux 9" : "Ubuntu 24.04 LTS"

  jump_host_name      = "nkp-jump-host"
  control_plane_names = [for i, _ in var.control_plane_ips : format("nkp-cp-%02d", i + 1)]
  worker_names        = [for i, _ in var.worker_ips : format("nkp-worker-%02d", i + 1)]
  hosts = merge(
    { (local.jump_host_name) = var.jump_host_ip },
    zipmap(local.control_plane_names, var.control_plane_ips),
    zipmap(local.worker_names, var.worker_ips),
  )

  ssh_key = trimspace(var.ssh_public_key)
  user_config = {
    users = [{
      name                = var.vm_user
      sudo                = "ALL=(ALL) NOPASSWD:ALL"
      shell               = "/bin/bash"
      lock_passwd         = true
      ssh_authorized_keys = [local.ssh_key]
    }]
  }

  # The default route is 0.0.0.0/0, not "default": cloud-init converts the v2
  # config itself on Rocky and rejects the netplan-only keyword.
  # NoCloud documents (cidata ISO on VMware). instance-id carries the OS so a
  # rebuilt VM is a new instance for cloud-init. fqdn is set with hostname:
  # RHEL-family cloud-init prefers the FQDN, and a datasource that reports
  # "localhost" (Nutanix ConfigDrive) would otherwise win.
  network_config = { for name, ip in local.hosts : name => {
    version = 2
    ethernets = { (var.nic_name) = {
      addresses   = ["${ip}/${var.network_prefix_length}"]
      routes      = [{ to = "0.0.0.0/0", via = var.network_gateway }]
      nameservers = { addresses = var.dns_servers }
    } }
  } }
  cloud_init = { for name, ip in local.hosts : name => {
    user_data      = "#cloud-config\n${yamlencode(merge({ hostname = name, fqdn = name }, local.user_config))}"
    meta_data      = yamlencode({ "instance-id" = "${name}-${var.os_distribution}", "local-hostname" = name })
    network_config = yamlencode(local.network_config[name])
  } }

  # For hypervisors whose cloud-init datasource has no network document
  # (Nutanix ConfigDrive): the static address is written as an OS file by
  # user-data and applied on first boot, and cloud-init's own DHCP config is
  # removed and disabled. The files match any ethernet NIC instead of naming
  # it: the name differs between images (Rocky GenericCloud boots with
  # net.ifnames=0 and gets eth0, Ubuntu names the NIC after its PCI slot), and
  # the VMs have a single NIC.
  netplan_config = { for name, ip in local.hosts : name => {
    version = 2
    ethernets = { nkp = {
      match       = { name = "e*" }
      addresses   = ["${ip}/${var.network_prefix_length}"]
      routes      = [{ to = "0.0.0.0/0", via = var.network_gateway }]
      nameservers = { addresses = var.dns_servers }
    } }
  } }
  nm_keyfile = { for name, ip in local.hosts : name => join("\n", [
    "[connection]",
    "id=nkp-static",
    "type=ethernet",
    "autoconnect=true",
    "autoconnect-priority=100",
    "",
    "[ipv4]",
    "method=manual",
    "address1=${ip}/${var.network_prefix_length},${var.network_gateway}",
    "dns=${join(";", var.dns_servers)};",
    "",
    "[ipv6]",
    "method=disabled",
    "",
  ]) }
  network_files = { for name, ip in local.hosts : name => (local.os_family == "ubuntu" ? {
    write_files = [{ path = "/etc/netplan/60-nkp.yaml", permissions = "0600", content = yamlencode({ network = local.netplan_config[name] }) },
    { path = "/etc/cloud/cloud.cfg.d/99-nkp-network.cfg", permissions = "0644", content = "network: {config: disabled}\n" }]
    runcmd = [["rm", "-f", "/etc/netplan/50-cloud-init.yaml"], ["netplan", "apply"]]
    } : {
    write_files = [{ path = "/etc/NetworkManager/system-connections/nkp-static.nmconnection", permissions = "0600", content = local.nm_keyfile[name] },
    { path = "/etc/cloud/cloud.cfg.d/99-nkp-network.cfg", permissions = "0644", content = "network: {config: disabled}\n" }]
    runcmd = [["sh", "-c", "rm -f /etc/NetworkManager/system-connections/cloud-init-*.nmconnection /etc/sysconfig/network-scripts/ifcfg-eth* /etc/sysconfig/network-scripts/ifcfg-ens*"], ["nmcli", "connection", "reload"], ["nmcli", "connection", "up", "nkp-static"]]
  }) }
  user_data_with_network = { for name, ip in local.hosts : name =>
    "#cloud-config\n${yamlencode(merge({ hostname = name, fqdn = name }, local.user_config, local.network_files[name]))}"
  }

  # trimspace: a heredoc argument ends with a newline that would otherwise
  # become an empty "# " line.
  disk_comment = join("\n", [for line in split("\n", trimspace(replace(replace(var.disk_comment, "{ceph_gb}", tostring(local.sizing.ceph_disk_gb)), "{volume_gb}", tostring(local.sizing.local_volume_gb)))) : "# ${line}"])
}
