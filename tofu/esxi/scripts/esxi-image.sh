#!/usr/bin/env bash
# Converts the cloud image to an ESXi thin disk at BASE_VMDK (create) or
# deletes it (destroy); called by terraform_data.base_disk of tofu/esxi.
set -euo pipefail
action="$1"
ssh_opts=(-p "$ESXI_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
# The remote commands are composed here on purpose, with local values.
# shellcheck disable=SC2029
remote() { ssh "${ssh_opts[@]}" "$ESXI_USER@$ESXI_HOST" "$@"; }
dir="$(dirname "$BASE_VMDK")"
case "$action" in
  # rmdir only removes the folders when they are empty: anything else left
  # in esxi_folder is kept.
  destroy) remote "vmkfstools -U '$BASE_VMDK' 2>/dev/null || true; rmdir '$dir' '$(dirname "$dir")' 2>/dev/null || true" ;;
  create)
    if remote "test -f '$BASE_VMDK'"; then exit 0; fi
    qcow="$("$SCRIPTS/fetch-image.sh" "$IMAGE_URL" "$CACHE_DIR" "$OS")"
    # Converted under a temporary name: an interrupted conversion is never
    # mistaken for a complete one on the next run.
    sparse="$CACHE_DIR/$OS-sparse.vmdk"
    if [ ! -s "$sparse" ]; then
      qemu-img convert -O vmdk -o subformat=monolithicSparse,adapter_type=lsilogic "$qcow" "$sparse.tmp"
      mv "$sparse.tmp" "$sparse"
    fi
    remote "mkdir -p '$dir'"
    scp -O -q -P "$ESXI_PORT" -o BatchMode=yes "$sparse" "$ESXI_USER@$ESXI_HOST:'$dir/$OS-upload.vmdk'"
    # Imported under a temporary name and renamed once complete, for the same
    # reason: the test -f above only sees a finished base disk.
    tmp="${BASE_VMDK%.vmdk}.tmp.vmdk"
    remote "vmkfstools -U '$tmp' >/dev/null 2>&1; vmkfstools -i '$dir/$OS-upload.vmdk' '$tmp' -d thin >/dev/null && vmkfstools -E '$tmp' '$BASE_VMDK' && rm -f '$dir/$OS-upload.vmdk'"
    ;;
  *) echo "usage: $0 create|destroy" >&2; exit 2 ;;
esac
