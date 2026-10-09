#!/usr/bin/env bash
# NKP Preprovisioned Toolkit - command wrapper.
#
#   ./deploy.sh [install] [options]      full installation (default command)
#   ./deploy.sh check [options]          preflight checks only
#   ./deploy.sh ping [options]           SSH + sudo connectivity test (ansible ping)
#   ./deploy.sh cis-harden [options]     apply the CIS Level 1 aligned baseline (subset of controls)
#   ./deploy.sh cis-audit [options]      audit that baseline; exits non-zero when a control fails
#   ./deploy.sh add-worker --ip <IP> [--name <NAME>] [options]
#                                        add a worker through Cluster API (Day-2)
#   ./deploy.sh remove-worker (--name <NODE> | --ip <IP>) [--yes] [--force] [--reboot] [options]
#                                        drain and remove a worker through Cluster API (Day-2)
#   ./deploy.sh remove-worker --cleanup-only --ip <IP> [--name <NODE>] [--yes] [--force] [--reboot] [options]
#                                        clean up the OS of a host that already left the cluster; a leftover
#                                        PreprovisionedInventory entry and its inventory.ini line are removed too,
#                                        and with --name the Ceph OSD of the former node is purged
#   ./deploy.sh tofu-init|tofu-plan|tofu-apply|tofu-destroy [tofu options]
#                                        OpenTofu provisioning of the VMs in tofu/<provider>/ (see tofu/README.md);
#                                        apply and destroy ask for confirmation
#   ./deploy.sh tofu-verify [options]    contract test of the created VMs (no NKP installation)
#   ./deploy.sh help                     show this help
#
# [options] are passed to ansible-playbook (to ansible for "ping"), for example:
#   ./deploy.sh install --tags jump_host,node_prep
#   ./deploy.sh -v
#   ./deploy.sh cis-audit -e cis_audit_strict=false
#   ./deploy.sh add-worker --help
# Settings that are lists (cis_extra_trusted_cidrs) need the JSON form of -e:
#   ./deploy.sh cis-harden -e '{"cis_extra_trusted_cidrs": ["10.20.0.0/24"]}'
#
# tofu-* commands: the provider (proxmox, esxi, vsphere or nutanix) is
# TOFU_PROVIDER, else tofu_provider in inventory.ini, else proxmox. Plan and
# apply of esxi and vsphere also need qemu-img, curl and an ISO tool on this
# computer (plus ssh and scp for esxi, python3 for vsphere). When inventory.ini exists, plan/apply/destroy get
# -var=os_distribution from os_profile and -var=sizing_profile from the
# optional key tofu_sizing_profile (pro-ultimate when absent); [tofu options]
# come last and override them:
#   ./deploy.sh tofu-apply -var=sizing_profile=contract-test
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="$REPO_ROOT/inventory.ini"
PLAYBOOK="$REPO_ROOT/ansible/site.yml"
VERIFY_PLAYBOOK="$REPO_ROOT/ansible/verify_hosts.yml"
CIS_HARDEN_PLAYBOOK="$REPO_ROOT/cis/ansible/cis_hardening.yml"
CIS_AUDIT_PLAYBOOK="$REPO_ROOT/cis/ansible/cis_audit.yml"
export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"

# Print the comment header of this file (the lines before "set -euo pipefail").
usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; }

# Value of a key in [all:vars] style "key = value" lines of inventory.ini;
# quotes and trailing comments are dropped. Empty when the key is missing.
inventory_var() {
  [ -f "$INVENTORY" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$INVENTORY" \
    | head -n 1 | sed -e 's/[[:space:]]*#.*$//' -e 's/^["'"'"']//' -e 's/["'"'"'][[:space:]]*$//'
}

# No command, or options only: default to "install" and keep the options.
case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
  ""|-*) command_arg="install" ;;
  *) command_arg="$1"; shift ;;
esac

case "$command_arg" in
  install|check|ping|cis-harden|cis-audit|tofu-verify) ;;
  add-worker|remove-worker)
    # The help of the Day-2 scripts needs neither inventory.ini nor Ansible.
    for arg in "$@"; do
      case "$arg" in
        --) break ;;
        -h|--help)
          if [ "$command_arg" = "add-worker" ]; then
            exec "$REPO_ROOT/scripts/add-node.sh" --help
          fi
          exec "$REPO_ROOT/scripts/remove-node.sh" --help
          ;;
      esac
    done
    ;;
  tofu-init|tofu-plan|tofu-apply|tofu-destroy)
    # OpenTofu needs neither inventory.ini nor Ansible; inventory.ini, when
    # present, only supplies tofu_provider, the OS (from os_profile) and the
    # optional tofu_sizing_profile.
    command -v tofu >/dev/null 2>&1 || { echo "tofu not found. Install OpenTofu on this computer (see tofu/README.md)." >&2; exit 127; }
    provider="${TOFU_PROVIDER:-$(inventory_var tofu_provider)}"
    provider="${provider:-proxmox}"
    case "$provider" in
      proxmox|nutanix) ;;
      esxi|vsphere)
        # The VMware modules download and convert the cloud image and build the
        # cidata ISO (and the OVA on vsphere) on this computer (tofu/scripts/)
        # when they create VMs: needed by plan and apply only, so that init and
        # destroy still work on a computer without these tools.
        case "$command_arg" in
          tofu-plan|tofu-apply)
            missing=()
            command -v qemu-img >/dev/null 2>&1 || missing+=("qemu-img (brew install qemu, or the qemu-utils package)")
            command -v curl >/dev/null 2>&1 || missing+=("curl")
            if ! command -v hdiutil >/dev/null 2>&1 && ! command -v xorriso >/dev/null 2>&1 && ! command -v genisoimage >/dev/null 2>&1; then
              missing+=("an ISO tool: hdiutil (macOS), xorriso or genisoimage")
            fi
            if [ "$provider" = vsphere ]; then
              command -v python3 >/dev/null 2>&1 || missing+=("python3")
            else
              command -v ssh >/dev/null 2>&1 || missing+=("ssh")
              command -v scp >/dev/null 2>&1 || missing+=("scp")
            fi
            if [ "${#missing[@]}" -gt 0 ]; then
              printf 'tofu/%s needs on this computer:\n' "$provider" >&2
              printf '  - %s\n' "${missing[@]}" >&2
              exit 127
            fi
            ;;
        esac
        ;;
      *) echo "Unknown tofu_provider: $provider (expected proxmox, esxi, vsphere or nutanix)" >&2; exit 1 ;;
    esac
    tofu_dir="$REPO_ROOT/tofu/$provider"
    if [ ! -d "$tofu_dir" ]; then
      echo "tofu provider directory not found: $tofu_dir" >&2
      exit 1
    fi

    tofu_vars=()
    if [ -f "$INVENTORY" ]; then
      os_profile="$(inventory_var os_profile)"
      case "$os_profile" in
        rocky*) tofu_vars+=("-var=os_distribution=rocky9") ;;
        ubuntu*) tofu_vars+=("-var=os_distribution=ubuntu24") ;;
        "") ;;
        *) echo "Unknown os_profile in inventory.ini: $os_profile" >&2; exit 1 ;;
      esac
      # Absent key: the module default (pro-ultimate) applies.
      sizing="$(inventory_var tofu_sizing_profile)"
      [ -n "$sizing" ] && tofu_vars+=("-var=sizing_profile=$sizing")
    fi

    cd "$tofu_dir"
    case "$command_arg" in
      tofu-init) exec tofu init "$@" ;;
      # ${arr[@]+"${arr[@]}"} keeps an empty array valid under set -u on bash 3.2.
      tofu-plan) exec tofu plan ${tofu_vars[@]+"${tofu_vars[@]}"} "$@" ;;
      tofu-destroy) exec tofu destroy ${tofu_vars[@]+"${tofu_vars[@]}"} "$@" ;;
      tofu-apply)
        tofu apply ${tofu_vars[@]+"${tofu_vars[@]}"} "$@"
        echo
        echo "inventory.ini snippet of the created VMs:"
        echo "  tofu -chdir=tofu/$provider output -raw ansible_inventory"
        echo "Then: ./deploy.sh tofu-verify"
        exit 0
        ;;
    esac
    ;;
  *) echo "Unknown command: $command_arg" >&2; usage >&2; exit 2 ;;
esac

# --- Controller preflight -----------------------------------------------------
if [ ! -f "$INVENTORY" ]; then
  echo "inventory.ini not found. Copy inventory.example.ini to inventory.ini and configure it." >&2
  exit 1
fi

perms=$(stat -c '%a' "$INVENTORY" 2>/dev/null || stat -f '%Lp' "$INVENTORY")
if [ "$perms" != "600" ]; then
  echo "note: inventory.ini holds credentials; consider: chmod 600 inventory.ini" >&2
fi

for bin in ansible-playbook ansible ansible-galaxy; do
  command -v "$bin" >/dev/null 2>&1 || { echo "$bin not found. Install Ansible on this computer (see README)." >&2; exit 127; }
done

installed=$(ansible-galaxy collection list 2>/dev/null || true)
for c in ansible.posix community.general community.crypto; do
  if ! grep -q "^$c " <<<"$installed"; then
    echo "==> Installing required Ansible collections"
    ansible-galaxy collection install -r "$REPO_ROOT/requirements.yml"
    break
  fi
done

# --- Run ----------------------------------------------------------------------
cd "$REPO_ROOT/ansible"
case "$command_arg" in
  ping)
    exec ansible -i "$INVENTORY" all -m ansible.builtin.ping "$@"
    ;;
  check)
    exec ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --tags preflight "$@"
    ;;
  cis-harden)
    exec ansible-playbook -i "$INVENTORY" "$CIS_HARDEN_PLAYBOOK" "$@"
    ;;
  cis-audit)
    exec ansible-playbook -i "$INVENTORY" "$CIS_AUDIT_PLAYBOOK" "$@"
    ;;
  install)
    exec ansible-playbook -i "$INVENTORY" "$PLAYBOOK" "$@"
    ;;
  tofu-verify)
    exec ansible-playbook -i "$INVENTORY" "$VERIFY_PLAYBOOK" -e preflight_skip_sizing=true "$@"
    ;;
  add-worker)
    exec "$REPO_ROOT/scripts/add-node.sh" "$@"
    ;;
  remove-worker)
    exec "$REPO_ROOT/scripts/remove-node.sh" "$@"
    ;;
esac
