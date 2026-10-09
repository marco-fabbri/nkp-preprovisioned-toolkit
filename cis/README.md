# CIS Level 1 aligned baseline (subset of controls)

This directory applies and audits an OS hardening baseline on the hosts of an NKP
preprovisioned deployment (**Rocky Linux 9** and **Ubuntu 24.04 LTS**). The controls
are taken from the CIS Benchmarks for those distributions and adjusted where
Kubernetes needs a different value.

> **Scope and disclaimer**
>
> - This is a **subset** of controls. It is **not** a complete or certified
>   implementation of any CIS Benchmark, and passing the audit here does **not**
>   mean a host is CIS compliant. For a compliance statement, scan the hosts with a
>   benchmark tool such as CIS-CAT or OpenSCAP.
> - The audit checks only the controls listed below, nothing else.
> - This project is not affiliated with, endorsed by or supported by the Center for
>   Internet Security (CIS) or Nutanix.

---

## What is applied and audited

The hardening and the audit read the same definitions
(`ansible/vars/baseline.yml`), so the audit checks exactly what the hardening sets.
The numbers below are the section numbers in `ansible/tasks/hardening.yml` and the
row numbers of the audit report.

| # | Control | Applied by the hardening | Checked by the audit (effective state) |
|---|---|---|---|
| 1 | Unused filesystem kernel modules | `install <module> /bin/false` and `blacklist <module>` for `cramfs`, `freevxfs`, `hfs`, `hfsplus`, `jffs2`, `udf` in `/etc/modprobe.d/60-cis-filesystems.conf` | `modprobe --showconfig` contains both lines for every module |
| 2 | Kernel parameters | `kernel.randomize_va_space=2`, `fs.suid_dumpable=0`, `tcp_syncookies=1`, `icmp_echo_ignore_broadcasts=1`, and for `all`/`default`: `send_redirects=0`, `accept_source_route=0`, `accept_redirects=0`, `secure_redirects=0`, `log_martians=1` (`/etc/sysctl.d/60-cis.conf`). Ubuntu: apport is disabled and `/etc/ufw/sysctl.conf` is aligned, because both would reset some of these values | Running values read with `sysctl` |
| 3 | Auditing, time sync and cron | Packages installed, services enabled and started: auditd, chrony, cron (`crond` on Rocky) | `systemctl is-active` for the three services |
| 4 | auditd rules | `/etc/audit/rules.d/50-cis.rules`: time changes, identity files, network environment files, sudoers, kernel module loading (syscall rules for `b64` and `b32`) | `auditctl -l` contains rules with the keys `time-change`, `identity`, `system-locale`, `scope`, `modules` |
| 5 | File permissions | `/etc/passwd`, `/etc/group` 0644 root:root; `/etc/shadow`, `/etc/gshadow` 0000 root:root on Rocky and 0640 root:shadow on Ubuntu; `/etc/crontab` 0600; `/etc/cron.{hourly,daily,weekly,monthly,d}` 0700 | Mode, owner and group of every path |
| 6 | Account and password defaults | `umask 027` for login shells (`/etc/profile.d/60-cis-umask.sh`); `INACTIVE=30` for accounts created later (`useradd -D`); `/etc/security/pwquality.conf` with `minlen = 14` and one character of each class | The three settings |
| 7 | Login warning banners | `/etc/issue`, `/etc/issue.net`, `/etc/motd` with a warning text, 0644 root:root | Files present, not empty, 0644, owned by root, without OS information escapes (`\m \r \s \v`) |
| 8 | OpenSSH daemon | `/etc/ssh/sshd_config.d/00-cis.conf`: `LogLevel INFO`, `MaxAuthTries 4`, `IgnoreRhosts yes`, `HostbasedAuthentication no`, `PermitEmptyPasswords no`, `PermitRootLogin no`, `ClientAliveInterval 300`, `ClientAliveCountMax 3`, `LoginGraceTime 60`, `X11Forwarding no`, `Banner /etc/issue.net`. Validated with `sshd -t` before sshd is restarted | Effective values from `sshd -T` |
| 9 | Host firewall | **Not applied on cluster nodes unless you opt in** (see [Host firewall on cluster nodes](#host-firewall-on-cluster-nodes)). Where it is applied: firewalld (Rocky, default `public` zone, whose other default services are not removed) or UFW (Ubuntu, incoming policy `deny`) enabled, SSH allowed on the port Ansible uses. The rules are written before the firewall is started | Rocky: `firewall-cmd --state`, SSH service and port, trusted sources, masquerading. Ubuntu: `ufw status verbose` (`Status: active`, default policies, SSH rule, trusted sources). Where it is not applied: `NOT APPLIED (by design ...)` plus the observed firewall state, never FAIL |

The audit prints one PASS/FAIL line per control for every host; a FAIL line names
the items that do not match. The play **fails** (non-zero exit code) for every host
where a control fails. Inside `./deploy.sh install` the report is printed for all
hosts and a gate play then stops the installation before the cluster is created if
any host failed the hardening or the audit. To get the report without failing:

```bash
./deploy.sh cis-audit -e cis_audit_strict=false
```

---

## Kubernetes nodes versus other hosts

The playbooks run on all inventory hosts. Settings that exist only because of
Kubernetes are applied to hosts in the `nkp_nodes` group and not to the jump host:

| Setting (cluster nodes only) | Benchmark default | Applied value | Reason |
|---|---|---|---|
| `net.ipv4.ip_forward` | `0` | `1` | Pod traffic is routed by the node |
| `net.ipv4.conf.{all,default}.rp_filter` | `1` | `0` | Strict reverse path filtering drops CNI traffic |
| `net.bridge.bridge-nf-call-iptables` / `ip6tables` | not set | `1` | Required by kube-proxy and the CNI; `overlay` and `br_netfilter` modules are loaded |
| Host firewall | enabled | **Not installed, not enabled** (default) | NKP prerequisite, see below |
| Firewall trusted sources (opt-in only) | none | Node subnet (`node_subnet_cidr`) and Pod CIDR (`pod_cidr`) | Node-to-node and pod-to-node traffic (API server, etcd, kubelet, CNI overlay, MetalLB) |
| Forwarded traffic (opt-in only) | deny | Ubuntu: UFW routed policy `allow`. Rocky: masquerading in the default firewalld zone, set by `node_firewalld_masquerade` | Pod traffic forwarded by the node |

On the jump host the firewall allows SSH only, and `ip_forward` / `rp_filter` are
left as they are (Docker manages forwarding there). If firewalld is started for the
first time on a host that is not a cluster node and Docker is running, Docker is
restarted once so that it registers its own firewalld zone; do not run the
hardening on the jump host while a cluster bootstrap is in progress.

### Host firewall on cluster nodes

The NKP 2.18 guide lists, among the prerequisites of pre-provisioned control plane
and worker machines, *"firewalld systemd service is disabled"*. A CIS benchmark asks
for the opposite. This baseline follows the platform vendor by default:

- On hosts in `nkp_nodes` the baseline does **not** install, configure or enable
  firewalld (Rocky) or UFW (Ubuntu). The guide does not mention UFW; Ubuntu is
  treated the same way because the reason is the same (a host firewall filters CNI
  and kube-proxy traffic), and because it is the conservative choice for the cluster.
- The audit reports control 9 on those hosts as
  `NOT APPLIED (by design on cluster nodes: NKP prerequisite, ...)` followed by the
  observed state (`firewalld active`, `ufw inactive`, ...). It does not count as a
  failure and does not stop the installation.
- A firewall that is already running on a node is left as it is. The `node_prep`
  role of the main toolkit adds the trusted sources to it and prints a notice. To
  go back to the vendor prerequisite run `sudo systemctl disable --now firewalld`
  (or `sudo ufw disable`); on a live cluster do it one node at a time. Nodes
  hardened by an earlier revision of this baseline are in this situation.
- **Opt-in:** set `cis_firewalld_on_nodes = true` (Rocky) or
  `cis_ufw_on_nodes = true` (Ubuntu). The baseline then installs the firewall on
  the nodes, writes the rules first and starts it afterwards (no window with the
  firewall up and the trusted sources missing), and the audit checks it. **This is
  outside the vendor prerequisites and has not been validated by Nutanix**: you own
  the consequences for support and for pod, LoadBalancer and NodePort traffic.

With the opt-in the rules are by **source**, not by port: nothing but SSH is opened
to clients outside the trusted sources. Clients outside the node subnet cannot
reach the Kubernetes API (6443), the dashboard or any LoadBalancer / NodePort
service on the node addresses or VIP unless their network is added to
`cis_extra_trusted_cidrs`.

### Variables

| Variable | Default | Purpose |
|---|---|---|
| `node_subnet_cidr` | Subnet of the default IPv4 interface of each host (role `common`) | Trusted source on cluster nodes |
| `pod_cidr` | `192.168.0.0/16` (role `common`) | Trusted source on cluster nodes |
| `cis_firewalld_on_nodes` | `false` (role `common`) | Rocky: install and enable firewalld on cluster nodes (outside the vendor prerequisites) |
| `cis_ufw_on_nodes` | `false` (role `common`) | Ubuntu: enable UFW on cluster nodes (outside the vendor prerequisites) |
| `cis_extra_trusted_cidrs` | `[]` | With the opt-in: extra trusted sources on cluster nodes, for example a jump host or admin network outside the node subnet |
| `node_firewalld_masquerade` | `true` (role `common`) | Rocky cluster nodes where firewalld runs: masquerading in the default zone, `true` = enabled, `false` = disabled. The same variable drives `node_prep`. `cis_firewalld_masquerade`, the earlier name, is still accepted |
| `cis_audit_strict` | `true` | Fail the audit play when a control fails |

Set them in `inventory.ini` (`[all:vars]`) or with `-e`. A list in an INI inventory
is written as `cis_extra_trusted_cidrs=["10.20.0.0/24"]`. With `-e` use the JSON
form, which keeps it a list:

```bash
./deploy.sh cis-harden -e '{"cis_extra_trusted_cidrs": ["10.20.0.0/24"]}'
```

The SSH rule uses the port Ansible connects to (`ansible_port`, default 22).

---

## What is deliberately not applied

| Item | Status | Why |
|---|---|---|
| SSH password authentication | Left as set by the main roles | Owner decision: `node_prep` and `jump_host` write `PasswordAuthentication yes` by default, as a console/SSH fallback. Set `ssh_password_authentication = false` in the inventory once key-based access is confirmed: the same roles then write `PasswordAuthentication no` (the baseline itself does not manage this directive) |
| Default account password | Left in place | Owner decision: `vm_default_password` is set by the main roles as a console fallback and does not meet the password quality rule of control 6 (which applies to later password changes). Change it for anything but a lab |
| SELinux enforcing (Rocky) | Not applied | `node_prep` sets SELinux to permissive on cluster nodes. The baseline does not change the SELinux mode |
| AppArmor (Ubuntu) | Not changed | Distribution defaults are kept |
| Inactivity lock on existing accounts | Not applied | `INACTIVE=30` is set for new accounts only; applying it to the existing Ansible / Cluster API account could lock the automation out |
| Unloading filesystem modules already in use | Not applied | The modules are blocked from loading; a module that is already loaded stays until the next reboot |
| Host firewall on cluster nodes | Not applied by default | NKP prerequisite (firewalld disabled), see [Host firewall on cluster nodes](#host-firewall-on-cluster-nodes) |
| Per-port firewall rules | Not applied | With the opt-in, cluster nodes trust the node subnet and the Pod CIDR as a whole |
| PAM faillock and password history, password ageing in `login.defs`, `su` restriction, sudo logging | Not applied | Out of scope of this subset |
| Mount options for `/tmp`, `/dev/shm`, separate partitions | Not applied | Depend on the disk layout of the preprovisioned hosts |
| AIDE, bootloader password and permissions, core dump limits, IPv6 parameters, journald / rsyslog settings, removal of unused services and packages, `cron.allow` / `at.allow`, SSH ciphers / MACs / access lists | Not applied | Out of scope of this subset |

Some of the applied items are classified as Level 2 in the benchmarks (the auditd
rules and the `udf` module); they are kept because they do not affect Kubernetes.

---

## Usage

The playbooks need `inventory.ini` and the Ansible collections from
`requirements.yml`; `deploy.sh` checks both. The wrappers in this directory only
call `deploy.sh`.

```bash
# Apply the baseline
./deploy.sh cis-harden            # or ./cis/harden.sh
./deploy.sh cis-harden --limit nkp_nodes

# Audit (read-only, non-zero exit code when a control fails)
./deploy.sh cis-audit             # or ./cis/audit.sh
./deploy.sh cis-audit -e cis_audit_strict=false
```

With `os_profile = rocky-cis` or `ubuntu-cis` in the inventory, `./deploy.sh install`
applies and audits the baseline automatically after node preparation (Stage 2.5 of
`ansible/site.yml`), before the cluster is created.

The hardening is idempotent and can be run again at any time. It connects as
`ansible_user` with sudo; connecting as `root` (through `ansible_user`,
`remote_user` or `-u`) is rejected because the baseline sets `PermitRootLogin no`.

---

## Why the baseline is applied with Ansible and not baked into an image

- Benchmark defaults such as `net.ipv4.ip_forward = 0` and strict `rp_filter` break
  pod networking. Applying the baseline after provisioning lets the deviations be
  limited to cluster nodes and kept next to the rest of the node configuration.
- Preprovisioned hosts already exist (bare metal or any hypervisor) and are not
  built from an image owned by this toolkit.
- The same playbooks can be run again later to re-apply or re-check the baseline
  without rebuilding hosts.

---

## Directory structure

```text
cis/
├── README.md
├── harden.sh                 # wrapper for ./deploy.sh cis-harden
├── audit.sh                  # wrapper for ./deploy.sh cis-audit
└── ansible/
    ├── cis_hardening.yml     # standalone playbook: apply the baseline
    ├── cis_audit.yml         # standalone playbook: audit the baseline
    ├── tasks/
    │   ├── hardening.yml     # tasks, also included by ansible/site.yml (Stage 2.5)
    │   └── audit.yml         # tasks, also included by ansible/site.yml (Stage 2.5)
    └── vars/
        └── baseline.yml      # controls shared by hardening and audit
```

A play that includes the task files must load role `common` and define the
handlers `Restart sshd daemon` and `Reload augenrules`.
