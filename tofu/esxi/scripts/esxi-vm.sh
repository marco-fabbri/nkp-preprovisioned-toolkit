#!/usr/bin/env bash
# Creates or destroys one VM on a standalone ESXi host over SSH; called by the
# terraform_data.vm provisioners of tofu/esxi. Only the VM folder VM_DIR is
# ever deleted, and only when it carries the owner token of this OpenTofu
# state (OWNER, written to VM_DIR/.nkp-owner at creation): a VM or folder of
# another lab with the same name is never touched.
set -euo pipefail
action="$1"
ssh_opts=(-p "$ESXI_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
# The remote commands are composed here on purpose, with local values.
# shellcheck disable=SC2029
remote() { ssh "${ssh_opts[@]}" "$ESXI_USER@$ESXI_HOST" "$@"; }
# scp -O hands the remote path to the remote shell: quote it (datastore names
# such as "datastore1 (1)" contain spaces).
upload() { scp -O -q -P "$ESXI_PORT" -o BatchMode=yes "$1" "$ESXI_USER@$ESXI_HOST:'$2'"; }

# Refuse anything but a VM folder of this module: /vmfs/volumes/<ds>/<folder>/<name>.
case "$VM_DIR" in
  /vmfs/volumes/*/*/"$NAME") ;;
  *) echo "refusing to manage $VM_DIR: not /vmfs/volumes/<datastore>/<folder>/$NAME" >&2; exit 1 ;;
esac
case "$OWNER" in
  "" | *[!A-Za-z0-9-]*) echo "invalid owner token: $OWNER" >&2; exit 1 ;;
esac
# How vim-cmd lists this VM: "[<datastore>] <folder>/<name>/<name>.vmx".
rel="${VM_DIR#/vmfs/volumes/}"
vmx_ref="[${rel%%/*}] ${rel#*/}/$NAME.vmx"

# Removes the VM of this state if present (power off, unregister) and its
# folder. Also used before a create: a create interrupted earlier leaves a
# tainted resource whose destroy provisioner never runs. Stops when the folder
# exists but is not owned by this state.
cleanup() {
  local state id
  state="$(remote "if [ -d '$VM_DIR' ]; then cat '$VM_DIR/.nkp-owner' 2>/dev/null || echo NO-OWNER; else echo NO-DIR; fi")"
  case "$state" in
    NO-DIR) return 0 ;;
    "$OWNER") ;;
    NO-OWNER) echo "refusing: $VM_DIR exists without the owner token of this OpenTofu state; if it is a leftover of this lab, remove it on the host" >&2; exit 1 ;;
    *) echo "refusing: $VM_DIR belongs to another OpenTofu state (owner $state)" >&2; exit 1 ;;
  esac
  id="$(remote "vim-cmd vmsvc/getallvms" | awk -v p="$vmx_ref" 'index($0, p) {print $1; exit}')"
  if [ -n "$id" ]; then
    remote "vim-cmd vmsvc/power.off $id >/dev/null 2>&1 || true; vim-cmd vmsvc/unregister $id"
  fi
  remote "rm -rf '$VM_DIR'"
}

case "$action" in
  destroy) cleanup ;;
  create)
    cleanup
    work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
    mkdir "$work/cidata"
    printf '%s' "$USER_DATA_B64" | base64 --decode > "$work/cidata/user-data"
    printf '%s' "$META_DATA_B64" | base64 --decode > "$work/cidata/meta-data"
    printf '%s' "$NETWORK_CONFIG_B64" | base64 --decode > "$work/cidata/network-config"
    "$SCRIPTS/make-cidata-iso.sh" "$work/cidata" "$work/cidata.iso"
    printf '%s' "$VMX_B64" | base64 --decode > "$work/$NAME.vmx"
    remote "mkdir -p '$VM_DIR' && printf '%s\n' '$OWNER' > '$VM_DIR/.nkp-owner'"
    upload "$work/cidata.iso" "$VM_DIR/cidata.iso"
    upload "$work/$NAME.vmx" "$VM_DIR/$NAME.vmx"
    remote "vmkfstools -i '$BASE_VMDK' '$VM_DIR/os.vmdk' -d thin >/dev/null && vmkfstools -X ${OS_GB}G '$VM_DIR/os.vmdk'"
    i=1
    for gb in $DATA_GB; do
      remote "vmkfstools -c ${gb}G -d thin '$VM_DIR/data$i.vmdk' >/dev/null"
      i=$((i + 1))
    done
    id="$(remote "vim-cmd solo/registervm '$VM_DIR/$NAME.vmx'")"
    remote "vim-cmd vmsvc/power.on $id >/dev/null"
    ;;
  *) echo "usage: $0 create|destroy" >&2; exit 2 ;;
esac
