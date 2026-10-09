# OpenTofu provisioning modules

The toolkit installs NKP on hosts that already exist. This directory holds the
optional OpenTofu modules that create those hosts, one directory per
virtualisation provider, all implementing the same contract so that the Ansible
part never knows which provider created the VMs.

| Directory | Platform | Provider | Status |
|---|---|---|---|
| `tofu/proxmox/` | Proxmox VE 8.2+ | [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) >= 0.100.0 | validated with a full NKP installation |
| `tofu/nutanix/` | Nutanix AHV through Prism Central pc.2024.3+ | [nutanix/nutanix](https://registry.terraform.io/providers/nutanix/nutanix/latest/docs) 2.x (v2 resources, v4 APIs) | validated with `tofu-verify` (Prism Central 7.6), no NKP installation |
| `tofu/esxi/` | standalone ESXi 7.0 U2+, free licence included | none: SSH, `vmkfstools`, `vim-cmd` | validated with `tofu-verify` (ESXi 8.0 U3e, free licence), no NKP installation |
| `tofu/vsphere/` | vCenter 7.0+ | [hashicorp/vsphere](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs) 2.x | validated with `tofu-verify` (vCenter 8.0 U3), no NKP installation |

`tofu/modules/layout/` is the shared module every provider calls: sizing
profiles, VM names, cloud-init documents and the inventory snippet live there
once. `tofu/scripts/` holds the helpers the VMware modules run on the
operator's computer (cloud image download, OVA build, cidata ISO).

## What a module creates

One jump host, 1 or 3 control plane nodes and one worker per address in
`worker_ips`, all from the same distribution cloud image (Rocky Linux 9
GenericCloud or Ubuntu 24.04 LTS), configured through cloud-init with a static
IPv4 address, the DNS servers, the hostname and an OS user (`vm_user`, default
`nutanix`) that accepts `ssh_public_key` and has passwordless sudo.

Every worker gets the disk layout the NKP 2.18 guide expects, on one SCSI
controller and always in this order; nothing is partitioned, formatted or
mounted by the module, that is the Ansible roles' job:

| Disk | SCSI slot | Purpose | Consumer |
|---|---|---|---|
| 1 | 0 | operating system | cloud image, grown to the profile size |
| 2 | 1 | raw block device, no partition table, no file system | Rook Ceph OSD (`ceph_osd_device`) |
| 3-6 | 2..5 | one file system each, mounted by UUID under `/mnt/disks/vol1..vol4` | local static provisioner (`local_volume_devices`, volume N = slot N+1) |

The jump host and the control plane nodes have the OS disk only. The data
disks are thin wherever the datastore allows it.

### Stable disk paths

Kernel names (`sda`, `sdb`, ...) do not follow the SCSI slot: on a Proxmox
worker of the lab the 110 GB disk in slot 2 came up as `sdb` and the 50 GB
Ceph disk in slot 1 as `sdc`, and the names changed at the next boot. The
inventory snippet therefore names every data disk by a stable link, and that
link must read the same on every worker, because the inventory carries one
value per disk role and Rook Ceph gets a single filter:

| Module | Stable link of the Ceph disk (slot 1) | How it is stable |
|---|---|---|
| `proxmox` | `/dev/disk/by-id/scsi-SQEMU_QEMU_HARDDISK_nkp-ceph` | disk serial set by the module (`nkp-ceph`, `nkp-vol1`..`nkp-vol4`) |
| `nutanix` | `/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:1:0` | SCSI slot of the AHV virtio-scsi controller |
| `esxi` | `/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:1:0` | SCSI unit of the PVSCSI controller |
| `vsphere` | `/dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:1:0` | SCSI unit of the PVSCSI controller |

AHV, ESXi and vSphere do not let a module choose the serial of a virtual disk,
so their modules use the `by-path` link, which encodes the controller and the
slot and is identical on VMs with the same virtual hardware. The paths were
read on test VMs of both images and are the defaults of `guest_ceph_device`
and `guest_local_volume_devices`; `./deploy.sh tofu-verify` fails if they do
not resolve to five different disks. `lsblk -o NAME,SIZE,HCTL` on a worker
shows the current mapping.

### NIC name

`virtual_ip_interface` in the snippet is the name the guest kernel gives the
VM NIC; kube-vip uses it on the control plane nodes. It depends on the image:
Rocky Linux 9 GenericCloud boots with `net.ifnames=0`, Ubuntu names the NIC
after its PCI slot.

| Module | Rocky Linux 9 | Ubuntu 24.04 |
|---|---|---|
| `proxmox` | `eth0` | `eth0` (renamed by the Proxmox cloud-init network config) |
| `nutanix` | `eth0` | `ens3` |
| `esxi` | `eth0` | `ens192` |
| `vsphere` | `eth0` | `ens192` |

`guest_nic_name` overrides the default on `nutanix`, `esxi` and `vsphere`.

### Sizing profiles (`sizing_profile`)

| Profile | Control plane | Worker | Expected layout (docs only) | OS disk | Ceph disk | Local volumes | Jump host |
|---|---|---|---|---|---|---|---|
| `pro-ultimate` (default) | 4 vCPU / 16384 MB | 8 vCPU / 32768 MB | 3 control planes, 4 workers | 80 GB | 50 GB | 4 x 110 GB | 4 vCPU / 8192 MB / 50 GB |
| `contract-test` | 2 vCPU / 2048 MB | 2 vCPU / 2048 MB | 1 control plane, 1 worker | 20 GB | 5 GB | 4 x 5 GB | 2 vCPU / 2048 MB / 20 GB |

`pro-ultimate` follows the Pro and Ultimate requirements of the NKP 2.18 guide,
the sizes the Ansible preflight checks (pre-provisioned infrastructure requires
one of those licences). The local volume disks get 110 GB because NKP needs
more than 100 GiB on each of them: Prometheus claims exactly 100 GiB and the
file system is a little smaller than the disk. The worker count is never
enforced: the module creates one worker per address in `worker_ips`.
`ceph_disk_size_gb` and `local_volume_size_gb` override the disk sizes of
either profile.

`contract-test` exists only to exercise a provider module: its VMs are far
below the NKP minimums and `./deploy.sh tofu-verify`, which skips the size
thresholds of the preflight (`preflight_skip_sizing=true`), is the only toolkit
command meant to run on them.

## The contract every provider implements

Inputs common to every module, defined once in
`tofu/modules/layout/variables.tf` (each provider directory links it as
`common_variables.tf`):

| Variable | Meaning |
|---|---|
| `os_distribution` | `rocky9` or `ubuntu24` |
| `sizing_profile` | `pro-ultimate` (default) or `contract-test` |
| `jump_host_ip` | static address of the jump host |
| `control_plane_ips` | 1 or 3 static addresses (3 for an etcd quorum) |
| `control_plane_vip` | kube-vip endpoint; exported to the inventory, not assigned to a VM |
| `worker_ips` | static addresses of the workers, one VM each |
| `network_gateway`, `network_prefix_length`, `dns_servers` | node subnet |
| `ssh_public_key`, `vm_user` | cloud-init user (default `nutanix`) |
| `ceph_disk_size_gb`, `local_volume_size_gb` | optional disk size overrides |

The common inputs are checked before anything is created: every address must
be IPv4, the VM addresses must all differ, `control_plane_vip` must not be a
VM address, the prefix length must lie between 8 and 30.

Provider-specific inputs carry the provider prefix (`nutanix_`, `esxi_`,
`vsphere_`; on Proxmox only the connection inputs do, the placement ones such as
`datastore_id`, `network_bridge` and `vm_id_base` are unprefixed) or, for the
names the guest sees, `guest_` (Nutanix, ESXi, vSphere). The cloud image URLs
are `rocky9_image_url` and `ubuntu24_image_url` in every module. They are
documented in each module's `variables.tf` and `terraform.tfvars.example`.

Outputs: `jump_host_ip`, `control_plane_ips`, `control_plane_vip`, `worker_ips`
and `ansible_inventory`, an `inventory.ini` snippet with the `[jump_host]`,
`[control_plane]`, `[workers]` and `[nkp_nodes:children]` groups and an
`[all:vars]` stub that carries every variable the preflight requires:
`ansible_user`, `os_profile`, `cluster_name` (`nkp-cluster`),
`control_plane_vip`, `virtual_ip_interface`, an example `metallb_ip_range`
(`10.10.10.90-10.10.10.99`, marked as such: the module cannot know which
addresses are free), `ceph_osd_device` and `local_volume_devices` (the stable
links above, the list as JSON on one line) and `tofu_sizing_profile` (read by
`deploy.sh`, ignored by Ansible). The snippet passes `./deploy.sh tofu-verify`
as it is; before `./deploy.sh install` the MetalLB pool must be replaced and
the NKP CLI path and checksums of `inventory.example.ini` added by hand.

Changing `os_distribution` rebuilds the VMs (`terraform_data.os_image` with
`replace_triggered_by`, or a hash of the VM definition on `esxi`), instead of
updating them in place with the old system disk. So does a change to the
cloud-init documents of a VM (address, gateway, DNS, key) on `nutanix`,
`esxi` and `vsphere`: cloud-init only applies them to a new instance, and
Prism Central does not even return them. On `esxi` and `vsphere` the cloud
images are cached on this computer and named after their URL, so a new image
URL gives a new image (Proxmox and Prism Central download the image themselves
under a fixed name). Resource names
are part of the contract so that an existing state keeps working across
toolkit versions.

## How to use

Prerequisites on your computer: OpenTofu >= 1.6 (>= 1.8 to run the
`tofu test` suites, which use mocked providers) and network access to the
provider endpoint. Plan and apply of `esxi` and `vsphere` also need
`qemu-img` (`brew install qemu` or the `qemu-utils` package), `curl` and an ISO
tool (`hdiutil` on macOS, `xorriso` or `genisoimage` on Linux), plus `ssh` and
`scp` with your key in the SSH agent for `esxi` and `python3` for `vsphere`;
`deploy.sh` checks them before calling OpenTofu (init and destroy do not need
them).

1. Configure the module (`<provider>` = `proxmox`, `nutanix`, `esxi` or
   `vsphere`):

   ```bash
   cp tofu/<provider>/terraform.tfvars.example tofu/<provider>/terraform.tfvars
   chmod 600 tofu/<provider>/terraform.tfvars
   # edit it: endpoint, credentials, placement, network, addresses, ssh_public_key
   ```

   `terraform.tfvars`, the state, the lock file and the `.cache/` directory of
   the VMware modules are gitignored.

2. Create the VMs:

   ```bash
   export TOFU_PROVIDER=<provider>   # or tofu_provider = <provider> in inventory.ini
   ./deploy.sh tofu-init
   ./deploy.sh tofu-plan
   ./deploy.sh tofu-apply            # OpenTofu asks for confirmation
   ```

   The `tofu-*` commands run in `tofu/<provider>/`; the provider comes from
   `TOFU_PROVIDER`, else `tofu_provider` in `inventory.ini`, else `proxmox`.
   When `inventory.ini` exists they also pass `-var=os_distribution` derived
   from `os_profile` (`rocky*` -> `rocky9`, `ubuntu*` -> `ubuntu24`), so the
   VMs always run the OS the Ansible roles will check, and
   `-var=sizing_profile` from the optional key `tofu_sizing_profile`
   (`pro-ultimate` when absent). Any extra argument is passed to OpenTofu
   after those and overrides them, for example
   `./deploy.sh tofu-apply -var=sizing_profile=contract-test` when no
   `inventory.ini` exists yet; the generated inventory then records
   `tofu_sizing_profile = contract-test` so that `tofu-plan` and
   `tofu-destroy` keep using it. A saved plan (`tofu plan -out`) rejects at
   apply time any `-var` that differs from `terraform.tfvars`: put the values
   in the file when you work with saved plans.

3. Build `inventory.ini` from the output and complete it:

   ```bash
   tofu -chdir=tofu/<provider> output -raw ansible_inventory > inventory.ini
   chmod 600 inventory.ini
   # replace the EXAMPLE MetalLB pool with free addresses of your node subnet,
   # add the NKP CLI path and checksums from inventory.example.ini, switch os_profile to rocky-cis / ubuntu-cis when
   # the CIS baseline is wanted, add tofu_provider = <provider>
   ```

4. Check the VMs against the contract, then install:

   ```bash
   ./deploy.sh tofu-verify
   ./deploy.sh install
   ```

`./deploy.sh tofu-destroy` removes the VMs (with confirmation).

## What `tofu-verify` checks

`./deploy.sh tofu-verify` runs `ansible/verify_hosts.yml` with `inventory.ini`
and `-e preflight_skip_sizing=true`. It is the acceptance test of a provider
module and the only command meant for `contract-test` VMs. It installs no
package and changes nothing persistent on the hosts. It checks:

- SSH and sudo access with `ansible_user` on every host, and the toolkit
  preflight with the vCPU, RAM and disk size thresholds skipped (a warning reminds
  that NKP must not be installed on undersized hosts);
- on every worker: `ceph_osd_device` and every entry of
  `local_volume_devices` resolve to a whole disk, each to a different one and
  none to the disk holding `/`; each is reported as
  `value -> /dev/<kernel name> <size>` and must reach the expected minimum size
  (`contract_ceph_min_gib` and `contract_local_volume_min_gib`, 1 GiB by
  default because the contract-test disks are below the NKP minimums);
- on the control plane nodes: `virtual_ip_interface` exists;
- cloud-init has finished on every host;
- the layer-2 path of the control plane VIP: `control_plane_vip/32` is added
  to `virtual_ip_interface` of the first control plane node, pinged three
  times from a worker and always removed again. A failure points at the
  virtual switch settings that block kube-vip (forged transmits, promiscuous
  mode or MAC learning). The test is skipped when the preflight considers the
  cluster as existing, which it does when `<cluster_name>.conf` is in the
  repository root: on hosts rebuilt for a new cluster remove that stale
  kubeconfig, or run the test with another `-e cluster_name=...`.

What it does **not** validate:

- the NKP size requirements (that is `./deploy.sh check` without
  `preflight_skip_sizing`, on hosts created with `pro-ultimate`);
- that the data disks are fast enough or on the right storage tier;
- the MetalLB pool, DNS resolution of external names, registry or internet
  reachability from the nodes;
- the NKP installation itself: a passing `tofu-verify` proves that the
  provider module delivers the agreed layout, not that NKP will install.

## Design choices

- **Cloud images used as they are, no Packer.** The modules boot the
  distribution's own cloud image (Rocky Linux 9 GenericCloud, Ubuntu 24.04)
  unmodified, and give each VM only what it needs at first boot through
  cloud-init: hostname, user, key, static address. Everything else (node
  preparation, CIS baseline) is done afterwards by the Ansible roles and by the
  NKP CLI, which prepares pre-provisioned nodes over SSH. A Packer-built golden
  image would add a second tool and a template to keep up to date only to
  change the disk format, and a second place that configures the operating
  system next to Ansible. Baked images become worth it for faster
  installations (packages and hardening already in the image) or air-gapped
  sites, which this toolkit does not target; they would then be built for every
  provider, not only vSphere.
- **Providers first, scripts only where a provider cannot help.** Proxmox and
  Nutanix are driven entirely by their providers. The vSphere module uses the
  provider for everything that lives in vCenter (content library, VMs, disks,
  uploads) and runs local scripts (`tofu/scripts/`) only for what happens on
  the operator's computer: downloading the cloud image, converting it into an
  OVA and building the cidata ISOs. The ESXi module is all scripts over SSH,
  because the free licence blocks the write API and `ovftool` that any provider
  would need. OpenTofu treats provisioners as a last resort: a resource created
  by a script is not re-read, so a change made by hand on the host is not
  detected by the next plan. The ESXi module limits the consequences with the
  owner token, the clean-up of half-built folders and a rebuild on any change.
- **cloud-init from a cidata ISO on VMware, not from `guestinfo`.** Passing
  cloud-init through the VM's `guestinfo` properties needs VMware Tools in the
  guest, which the Rocky Linux GenericCloud image does not ship. A NoCloud ISO
  on a virtual CD-ROM works with both images unmodified.

## Proxmox notes

- The API token (or user) needs the privileges listed in the bpg/proxmox
  provider documentation; `image_datastore` must allow the `import` content
  type (Proxmox VE 8.2+), which is where the cloud images are downloaded
  before being imported as the scsi0 disk of every VM. `template_file_id`
  points at an image already present on the node instead.
- The QEMU guest agent is disabled on purpose: the cloud images do not ship
  it, and with the agent enabled the provider waits 15 minutes for an answer
  on every refresh and creation.
- VM IDs: `vm_id_base` for the jump host, `+1..+3` for the control planes,
  `+4` onwards for the workers; the worker IDs do not move when only one
  control plane is created.
- The data disks carry the serials `nkp-ceph` and `nkp-vol1`..`nkp-vol4`; the
  Proxmox cloud-init network configuration names the first NIC `eth0` on both
  images.

## Nutanix AHV notes

- Prism Central is required (the v2 resources use the v4 APIs, stable from
  pc.2024.3); Prism Element alone is not enough. The Prism Central user
  (`nutanix_username`) must be allowed to create images and VMs on the target
  cluster.
- Prism Central downloads the cloud images from `rocky9_image_url` and
  `ubuntu24_image_url`: the URLs must be reachable from Prism Central.
- cloud-init arrives through the AHV guest customization (ConfigDrive), which
  has no network document: the static address is written by user-data
  (netplan on Ubuntu, a NetworkManager keyfile on Rocky, both matching any
  NIC name) and cloud-init's own DHCP config is disabled. `fqdn` is set with
  the hostname, otherwise Rocky keeps the `localhost` the ConfigDrive reports.
- Correcting an address, the gateway, the DNS servers or the key rebuilds the
  VM: Prism Central does not return the cloud-init payload, so the module
  tracks a hash of it.
- Subnets with AHV IPAM: set `nutanix_subnet_ipam = true`. The module then
  also reserves each VM address on AHV, so that the subnet's DHCP pool cannot
  hand it to another VM. The VM addresses must lie inside one of the subnet's
  IP pools: AHV accepts a reservation outside the pools at creation but
  refuses to power the VM on with the misleading message "no host has enough
  resources". Keep `control_plane_vip` and the MetalLB range outside the pools.
  Without IPAM (the default) only cloud-init sets the address.
- Prism Central attaches the ConfigDrive as a CD-ROM of its own and reports
  `should_assign_ip = false` once an IPAM address is assigned: both are
  ignored after creation, so a plan right after an apply shows no changes.
- Provider 2.5 crashes ("Plugin did not respond") instead of reporting some
  Prism Central errors, for example an HTTP 500 while Prism Central is busy:
  run the command again.

## ESXi notes

- The module needs no provider and no vCenter: it drives the host over SSH
  with `vmkfstools` and `vim-cmd`, which the free licence (vSphere
  Hypervisor, read-only API, no `ovftool` deployment) allows. Enable SSH on
  the host and put your public key in `/etc/ssh/keys-root/authorized_keys`;
  the module uses your SSH agent and stores no password.
- The cloud image is downloaded and converted to a VMDK on your computer
  (`.cache/` of the module), uploaded once per OS and imported as a thin disk
  under `<esxi_folder>/images/`; every VM gets a copy grown to the profile
  size, a `.vmx` generated by the module (PVSCSI, vmxnet3,
  `disk.EnableUUID`) and its own cidata ISO on a SATA CD-ROM.
- There is no in-place update: any change to a VM (OS, size, cloud-init,
  hardware) rebuilds it. `destroy` powers the VMs off, unregisters them and
  deletes only their folders and the base disk.
- Every VM folder carries the owner token of the OpenTofu state that created
  it (`.nkp-owner`): the scripts only clean up or delete folders with that
  token, so two labs on the same host never touch each other's VMs, even with
  the same VM names. A folder of the same name without the token stops the
  apply with a message.
- A create interrupted half-way leaves a tainted resource; the next apply
  removes the half-built folder and creates the VM again. The image
  conversion and the base disk import write a temporary file and rename it
  when complete, so an interrupted one is never reused.
- `esxi_folder` is a single folder name; datastore names with spaces (such as
  `datastore1 (1)`) are fine.
- The free licence limits a VM to 8 vCPU, the size of a `pro-ultimate`
  worker.

## vSphere notes

- vCenter is required: the module clones the VMs from a content library
  item, a vCenter feature. It places the VMs in the root resource pool of a
  compute cluster (`vsphere_cluster`); a standalone host inside vCenter needs
  a cluster around it.
- The OVA is built on your computer from the distribution cloud image
  (`tofu/scripts/build-ova.sh`: streamOptimized VMDK plus a minimal OVF with
  PVSCSI, vmxnet3 and a SATA CD-ROM), imported into a local content library
  the module creates, and cloned for every VM with the disk grown to the
  profile size. Each VM gets its own cidata ISO uploaded to the datastore.
  The OVA and the library item are named after the OS and a hash of the image
  URL, so a new image never collides with the one it replaces.
- An import that fails half-way can leave the library item in vCenter without
  recording it in the state (a provider limitation): the next apply then fails
  with "a library item with the name ... exists". Remove that item from the
  `vsphere_content_library` library (vSphere Client, or
  `govc library.rm <library>/<item>`) and apply again.
- kube-vip and MetalLB answer ARP for addresses no NIC owns, with the VM's own
  MAC, so the default security policy of a standard vSwitch should allow it.
  Not verified: the lab's nested vSwitch accepted promiscuous mode, MAC
  changes and forged transmits, which nested ESXi needs anyway.
  `./deploy.sh tofu-verify` tests the VIP path on your network.
- Rocky VMs are declared as `rhel9_64Guest`: `rockylinux_64Guest` needs a
  virtual hardware newer than the OVA's vmx-19, and such VMs do not power on.

## Adding a provider

Create `tofu/<provider>/` with:

- `common_variables.tf`, a symbolic link to `../modules/layout/variables.tf`;
- a `module "layout"` call that passes the common inputs plus
  `provider_name`, the NIC name of the provider's images (`nic_name`,
  `nic_comment`) and the stable paths of the Ceph and local volume disks
  (`ceph_osd_device`, `local_volume_devices`, `disk_comment`);
- the VMs, built from `module.layout` (`sizing`, `*_names`, `cloud_init` or
  `user_data_with_network`), with the six-disk worker layout in slot order;
- the standard outputs, `ansible_inventory` being `module.layout.ansible_inventory`;
- a rebuild of the VMs when `os_distribution` changes;
- a `terraform.tfvars.example` with `10.10.10.x` addresses and a
  `tests/*.tftest.hcl` that runs with a mocked provider.

Run `tofu fmt -check`, `tofu validate` and `tofu test`, add the directory to
the CI matrix, then create `contract-test` VMs and run
`./deploy.sh tofu-verify` against them. Read the NIC name and the `by-path`
links on a test VM of each image before setting them as defaults.
