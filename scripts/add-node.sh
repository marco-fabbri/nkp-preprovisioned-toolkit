#!/usr/bin/env bash
# ==============================================================================
# Script: add-node.sh - Add a worker node to the NKP cluster through Cluster API
# ==============================================================================
# Usage:
#   ./scripts/add-node.sh --ip <NODE_IP> [--name <NODE_NAME>] [ansible-playbook options]
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="$REPO_ROOT/inventory.ini"
PLAYBOOK="$REPO_ROOT/ansible/add_worker.yml"
export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"

usage() {
  cat <<EOF
Usage: $0 --ip <NODE_IP> [--name <NODE_NAME>] [ansible-playbook options]

Prepares the host like the original workers, adds its IP to the worker
PreprovisionedInventory, scales the node pool by +1 through Cluster API, waits
for the node to be Ready and records it under [workers] in inventory.ini.
The host is reached with the same SSH user as the existing workers. A failed
preflight or preparation stops the run before the cluster is touched; the node
pool must have as many replicas as hosts in its inventory.

Options:
  --ip <IP>       IPv4 address of the new worker (mandatory). It must not be the
                  control plane VIP, an existing inventory host or an address
                  inside the MetalLB pool.
  --name <NAME>   Hostname to set on the node and inventory name (optional,
                  RFC 1123 label). Without it the OS hostname is left unchanged
                  and the inventory name is nkp-worker-<last octet>.
  -h, --help      Display this help message

Any other argument is passed to ansible-playbook (for example -v).

Example:
  $0 --ip 10.10.10.89 --name nkp-worker-03
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

is_rfc1123_label() {
  local re='^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$'
  [[ "$1" =~ $re ]]
}

NODE_IP=""
NODE_NAME=""
EXTRA_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ip)
      [ "$#" -ge 2 ] || die "option $1 requires a value"
      NODE_IP="$2"
      shift 2
      ;;
    --name)
      [ "$#" -ge 2 ] || die "option $1 requires a value"
      NODE_NAME="$2"
      shift 2
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

[ -n "$NODE_IP" ] || die "option --ip is mandatory"
is_ipv4 "$NODE_IP" || die "'$NODE_IP' is not a valid IPv4 address"
if [ -n "$NODE_NAME" ]; then
  is_rfc1123_label "$NODE_NAME" || die "'$NODE_NAME' is not a valid hostname (lowercase letters, digits and '-', max 63 characters)"
fi
[ -f "$INVENTORY" ] || die "inventory.ini not found in $REPO_ROOT"

# Values are validated above, so they can be embedded in JSON without escaping.
EXTRA_VARS="{\"worker_ip\": \"$NODE_IP\""
if [ -n "$NODE_NAME" ]; then
  EXTRA_VARS="$EXTRA_VARS, \"worker_name\": \"$NODE_NAME\""
fi
EXTRA_VARS="$EXTRA_VARS}"

echo "=============================================================================="
echo "Adding worker node to the NKP cluster through Cluster API"
echo "Target IP  : $NODE_IP"
if [ -n "$NODE_NAME" ]; then echo "Target name: $NODE_NAME"; fi
echo "=============================================================================="

# ${arr[@]+...} keeps bash 3.2 from failing on an empty array under 'set -u'.
exec ansible-playbook -i "$INVENTORY" "$PLAYBOOK" -e "$EXTRA_VARS" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
