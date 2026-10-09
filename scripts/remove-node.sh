#!/usr/bin/env bash
# ==============================================================================
# Script: remove-node.sh - Remove a worker node from the NKP cluster through Cluster API
# ==============================================================================
# Usage:
#   ./scripts/remove-node.sh (--name <NODE_NAME> | --ip <NODE_IP>) [--yes] [--force] [--reboot]
#   ./scripts/remove-node.sh --cleanup-only --ip <NODE_IP> [--name <NODE_NAME>] [--yes] [--force] [--reboot]
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="$REPO_ROOT/inventory.ini"
PLAYBOOK="$REPO_ROOT/ansible/remove_worker.yml"
export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"

usage() {
  cat <<EOF
Usage: $0 (--name <NODE_NAME> | --ip <NODE_IP>) [--yes] [--force] [--reboot] [ansible-playbook options]
       $0 --cleanup-only --ip <NODE_IP> [--name <NODE_NAME>] [--yes] [--force] [--reboot] [ansible-playbook options]

Removes one worker: the target is matched exactly, the Machine is marked for
deletion and the node pool is scaled by -1 (Cluster API cordons, drains and
deletes the node), the IP is removed from the PreprovisionedInventory, the Ceph
OSD of the node is purged, the host OS is cleaned up and the host line is
removed from inventory.ini. Control plane nodes are never removed.

Options:
  --name <NAME>    Exact Kubernetes node name, as shown by 'kubectl get nodes'
                   (use either --name or --ip). With --cleanup-only: the name
                   the host had as a node, so that its Ceph OSD can be purged
  --ip <IP>        Exact IPv4 address of the node
  -y, --yes        Do not ask for confirmation (required when not run from a terminal)
  --force          Proceed even if Rook Ceph is not HEALTH_OK. With --cleanup-only:
                   also clean a host that is not recognised as a former member
                   of this cluster (see below)
  --reboot         Reboot the host at the end of the OS cleanup
  --cleanup-only   Skip the drain and scale-in: clean up the OS of a host that is
                   no longer a cluster node (re-run after a failed cleanup, or
                   after Cluster API finished a removal on its own). A leftover
                   PreprovisionedInventory entry and the inventory.ini line of
                   the host are removed too. Requires --ip and the cluster
                   kubeconfig on the jump host. The Ceph OSD of the former node
                   is purged only when --name is given too.
                   Refused when the host is still a node or Machine, when a
                   pending Machine still needs its address (failed add-worker:
                   the message explains the rollback), and, unless --force is
                   given, when the host is unknown to this cluster or its
                   kubelet points to another cluster.
  -h, --help       Display this help message

Any other argument is passed to ansible-playbook (for example -v).

Examples:
  $0 --name nkp-worker-02
  $0 --ip 10.10.10.87 --yes
  $0 --cleanup-only --ip 10.10.10.87 --name nkp-worker-02
EOF
}

die() {
  echo "ERROR: $1" >&2
  echo "Run '$0 --help' for usage." >&2
  exit 2
}

is_ipv4() {
  local ip="$1" octet
  local re='^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$'
  [[ "$ip" =~ $re ]] || return 1
  for octet in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
    [ "$octet" -le 255 ] || return 1
  done
}

# Kubernetes node names are RFC 1123 subdomains.
is_node_name() {
  local re='^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$'
  [[ "$1" =~ $re ]]
}

TARGET_NAME=""
TARGET_IP=""
ASSUME_YES=false
FORCE=false
REBOOT=false
CLEANUP_ONLY=false
EXTRA_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)
      [ "$#" -ge 2 ] || die "option $1 requires a value"
      TARGET_NAME="$2"
      shift 2
      ;;
    --ip)
      [ "$#" -ge 2 ] || die "option $1 requires a value"
      TARGET_IP="$2"
      shift 2
      ;;
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --reboot)
      REBOOT=true
      shift
      ;;
    --cleanup-only)
      CLEANUP_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do EXTRA_ARGS+=("$1"); shift; done
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

# Normal mode: one of --name or --ip. Cleanup-only: --ip, plus an optional
# --name that is passed as ceph_host (the node name the host had in Ceph).
CEPH_HOST=""
if [ -n "$TARGET_IP" ]; then
  is_ipv4 "$TARGET_IP" || die "'$TARGET_IP' is not a valid IPv4 address"
fi
if [ -n "$TARGET_NAME" ]; then
  is_node_name "$TARGET_NAME" || die "'$TARGET_NAME' is not a valid Kubernetes node name"
fi
if [ "$CLEANUP_ONLY" = true ]; then
  [ -n "$TARGET_IP" ] || die "--cleanup-only requires --ip"
  TARGET="$TARGET_IP"
  CEPH_HOST="$TARGET_NAME"
else
  if [ -n "$TARGET_NAME" ] && [ -n "$TARGET_IP" ]; then
    die "use either --name or --ip, not both (both are accepted only with --cleanup-only)"
  fi
  if [ -z "$TARGET_NAME" ] && [ -z "$TARGET_IP" ]; then
    die "specify the worker to remove with --name or --ip"
  fi
  TARGET="${TARGET_IP:-$TARGET_NAME}"
fi
[ -f "$INVENTORY" ] || die "inventory.ini not found in $REPO_ROOT"

# Without a terminal the confirmation prompt cannot be answered: require an explicit --yes.
if [ "$ASSUME_YES" != true ] && [ ! -t 0 ]; then
  die "standard input is not a terminal: pass --yes to confirm the removal non-interactively"
fi

if [ "$CLEANUP_ONLY" = true ] && [ "$ASSUME_YES" != true ]; then
  printf 'The OS of host %s will be cleaned up (kubeadm reset, Ceph loop device or signature on the raw OSD disk, Kubernetes directories).\n' "$TARGET"
  if [ -n "$CEPH_HOST" ]; then
    printf 'The down Ceph OSD of former node %s will be purged from the Ceph cluster.\n' "$CEPH_HOST"
  else
    printf 'No --name given: the Ceph OSD of the former node is NOT purged.\n'
  fi
  if [ "$FORCE" = true ]; then
    printf 'WARNING: --force also cleans a host that is not recognised as a former member of this cluster.\n'
  fi
  printf 'Type the IP address to confirm: '
  read -r answer
  [ "$answer" = "$TARGET" ] || die "confirmation does not match: nothing was changed"
  ASSUME_YES=true
fi

# With --cleanup-only, --force lifts the "former member of this cluster" check.
CLEANUP_FORCE=false
if [ "$CLEANUP_ONLY" = true ] && [ "$FORCE" = true ]; then
  CLEANUP_FORCE=true
fi

# Values are validated above, so they can be embedded in JSON without escaping.
EXTRA_VARS="{\"target_node\": \"$TARGET\", \"assume_yes\": $ASSUME_YES, \"force\": $FORCE, \"cleanup_only\": $CLEANUP_ONLY"
EXTRA_VARS="$EXTRA_VARS, \"cleanup_force\": $CLEANUP_FORCE, \"reboot_after_cleanup\": $REBOOT"
if [ -n "$CEPH_HOST" ]; then
  EXTRA_VARS="$EXTRA_VARS, \"ceph_host\": \"$CEPH_HOST\""
fi
EXTRA_VARS="$EXTRA_VARS}"

echo "=============================================================================="
if [ "$CLEANUP_ONLY" = true ]; then
  echo "Cleaning up the OS of former worker: $TARGET"
  echo "A leftover PreprovisionedInventory entry and its inventory.ini line are removed too."
  if [ -n "$CEPH_HOST" ]; then
    echo "The down Ceph OSD of former node $CEPH_HOST is purged."
  else
    echo "No --name given: the Ceph OSD of the former node is not purged."
  fi
else
  echo "Removing worker from the NKP cluster through Cluster API: $TARGET"
  echo "The node is drained and deleted, its Ceph OSD is lost and the host OS is cleaned up."
fi
echo "=============================================================================="

# ${arr[@]+...} keeps bash 3.2 from failing on an empty array under 'set -u'.
exec ansible-playbook -i "$INVENTORY" "$PLAYBOOK" -e "$EXTRA_VARS" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
