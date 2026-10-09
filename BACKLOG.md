# Backlog

Short roadmap for the NKP Preprovisioned Toolkit. Its scope is node preparation,
cluster creation, Kommander installation, worker scaling and the CIS Level 1 aligned
baseline (subset of controls), plus optional OpenTofu modules that create the hosts
with the expected layout.

The validation status of the current revision is stated in
[README.md](README.md#known-limitations--validation-status), not here.

## Implemented

- Rocky Linux 9 and Ubuntu 24.04 LTS, selected with `os_profile`.
- CIS Level 1 aligned baseline (subset of controls) with a nine-control audit; a
  gate play stops the installation before the cluster is created when any host
  failed it (`rocky-cis`, `ubuntu-cis`). The host firewall control is not applied on
  cluster nodes unless opted in (NKP prerequisite).
- Worker scale-out and scale-in through Cluster API (`PreprovisionedInventory` plus
  `MachineDeployment` scaling). Validated in the lab on every OS profile: remove then
  re-add the same worker, with the Ceph OSD purged and recreated.
- Preflight checks for address overlap with the Pod and Service CIDRs, sizing, OS,
  worker data disks, VIP and API port.
- Worker disk layout of the NKP guide by default: a raw disk for the Rook Ceph OSD
  (`ceph_osd_device`) and one disk per local volume (`local_volume_devices`); the
  loop device and bind-mounted directory shortcuts remain as opt-ins.
- Licence activation flow: the installation summary prints the Cluster UUID the
  licence is issued for (the Cluster API cluster object) and reads the activated
  tier back from the cluster; validated in the lab with an NKP Ultimate key.
- OpenTofu provisioning modules under `tofu/<provider>/` with one contract and a
  shared layout module: Proxmox, Nutanix AHV, standalone ESXi (free licence
  included) and vSphere, plus the contract test `./deploy.sh tofu-verify`.

## Open items

| ID | Item | Notes |
|---|---|---|
| BL-05 | Node-only preflight entry point for `add-worker` | Today the whole preflight role runs, so `downloads/nkp` and its checksums are still required at Day-2 |
| BL-06 | Run the CIS audit on a worker added on a `-cis` profile | The baseline is applied; the audit must be run by hand |
| BL-07 | Single source for the node firewall rules | `node_prep` and the CIS tasks use the same variables but separate task files |
| BL-08 | Lab validation of the opt-in host firewall on nodes | `cis_firewalld_on_nodes` / `cis_ufw_on_nodes` and `node_firewalld_masquerade=false` are untested on real hosts |
| BL-09 | Optional SSH host key checking | Disabled today in `ansible/ansible.cfg` and in the jump host to node SSH commands |
| BL-11 | Password authentication off by default on `-cis` profiles | Today `ssh_password_authentication` (default `true`) writes `PasswordAuthentication yes` or `no` on every profile |
| BL-13 | SSH port other than 22 for Cluster API | The host firewall rules follow `ansible_port`; the `PreprovisionedInventory` still uses port 22 |
| BL-14 | Automated rollback of a failed `add-worker` | Today the failure message prints the manual `kubectl` steps |
| BL-17 | NKP installation on VMs created by `tofu/nutanix`, `tofu/esxi` and `tofu/vsphere` | Validated with `./deploy.sh tofu-verify` only |
| BL-18 | Remove the directory shortcut data at `remove-worker` cleanup | With `local_volume_devices = []` the directories `/var/local-disks/volN` and their bind mounts are left on the host |

## Out of scope

- Provisioning of bare-metal servers, and of virtual machines on providers without a
  module under `tofu/`.
- Air-gapped installation, cluster upgrades, control plane scaling.
- Full CIS Benchmark coverage or certification.
