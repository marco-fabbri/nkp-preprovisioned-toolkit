#!/usr/bin/env bash
# Checks the ESXi scripts of tofu/esxi without a host: ssh, scp and qemu-img
# are replaced by fakes that log what they receive and answer from environment
# variables; fetch-image.sh and make-cidata-iso.sh by stubs. It checks that a
# create never touches a VM or folder of another state, that an interrupted
# conversion or import is never reused, and that datastore names with spaces
# survive the copy.
# Usage: tofu/esxi/scripts/tests/esxi-scripts-test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scripts="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0

mkdir -p "$work/bin" "$work/scripts"
# ssh: log the remote command, answer the few queries the scripts make.
cat > "$work/bin/ssh" <<'EOF'
#!/usr/bin/env bash
cmd="${*: -1}"
printf '%s\n' "$cmd" >> "$FAKE_LOG"
case "$cmd" in
  *"vim-cmd vmsvc/getallvms"*) cat "$FAKE_GETALLVMS" ;;
  *".nkp-owner"*"NO-DIR"*) printf '%s\n' "$FAKE_DIR_STATE" ;;
  "test -f "*) exit "${FAKE_BASE_EXISTS:-1}" ;;
  *"solo/registervm"*) echo 42 ;;
esac
exit 0
EOF
cat > "$work/bin/scp" <<'EOF'
#!/usr/bin/env bash
printf 'scp %s\n' "${*: -1}" >> "$FAKE_LOG"
EOF
# qemu-img: write a partial file to the target, then succeed or fail.
cat > "$work/bin/qemu-img" <<'EOF'
#!/usr/bin/env bash
printf 'partial' > "${*: -1}"
exit "${FAKE_QEMU_RC:-0}"
EOF
cat > "$work/scripts/fetch-image.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$2"; printf 'qcow' > "$2/$3.qcow2"; printf '%s\n' "$2/$3.qcow2"
EOF
cat > "$work/scripts/make-cidata-iso.sh" <<'EOF'
#!/usr/bin/env bash
printf 'iso' > "$2"
EOF
chmod +x "$work/bin/"* "$work/scripts/"*
export PATH="$work/bin:$PATH" FAKE_LOG="$work/log" FAKE_GETALLVMS="$work/getallvms"
export ESXI_HOST=192.0.2.1 ESXI_USER=root ESXI_PORT=22 SCRIPTS="$work/scripts"

check() { # check <description> <condition...>
  local desc="$1"; shift
  if "$@"; then echo "ok   - $desc"; else echo "FAIL - $desc"; fails=$((fails + 1)); fi
}
logged() { grep -qF -- "$1" "$FAKE_LOG"; }
not_logged() { ! grep -qF -- "$1" "$FAKE_LOG"; }

vm_env() { # vm_env <datastore> <owner of the existing folder: NO-DIR | token>
  export NAME=nkp-cp-01 VM_DIR="/vmfs/volumes/$1/nkp/nkp-cp-01" OWNER=token-mine
  export BASE_VMDK="/vmfs/volumes/$1/nkp/images/ubuntu24-abc.vmdk" OS_GB=20 DATA_GB=""
  export FAKE_DIR_STATE="$2"
  export VMX_B64 USER_DATA_B64 META_DATA_B64 NETWORK_CONFIG_B64
  VMX_B64="$(printf 'vmx' | base64)"; USER_DATA_B64="$VMX_B64"; META_DATA_B64="$VMX_B64"; NETWORK_CONFIG_B64="$VMX_B64"
  : > "$FAKE_LOG"
}

# 1. A same-named VM in another folder of the host is left alone.
vm_env datastore1 NO-DIR
printf '%s\n' "Vmid  Name  File  Guest OS" "7  nkp-cp-01  [datastore1] other-lab/nkp-cp-01/nkp-cp-01.vmx  ubuntu64Guest" > "$FAKE_GETALLVMS"
"$scripts/esxi-vm.sh" create >/dev/null 2>&1
check "create leaves a same-named VM of another folder registered" not_logged "vmsvc/unregister 7"
check "create writes the owner token right after mkdir" logged "printf '%s\\n' 'token-mine' > '/vmfs/volumes/datastore1/nkp/nkp-cp-01/.nkp-owner'"

# 2. A folder owned by another state stops the create and is not deleted.
vm_env datastore1 token-other
printf '%s\n' "Vmid  Name  File  Guest OS" "8  nkp-cp-01  [datastore1] nkp/nkp-cp-01/nkp-cp-01.vmx  ubuntu64Guest" > "$FAKE_GETALLVMS"
"$scripts/esxi-vm.sh" create >/dev/null 2>&1; rc=$?
check "create refuses a folder that belongs to another state" test "$rc" -ne 0
check "the other state's folder is not deleted" not_logged "rm -rf '/vmfs/volumes/datastore1/nkp/nkp-cp-01'"
check "the other state's VM is not unregistered" not_logged "vmsvc/unregister 8"

# 3. A folder of this state (create interrupted earlier) is cleaned and rebuilt.
vm_env datastore1 token-mine
"$scripts/esxi-vm.sh" create >/dev/null 2>&1; rc=$?
check "create cleans a half-built folder of this state" test "$rc" -eq 0
check "the own registered VM is unregistered before the rebuild" logged "vmsvc/unregister 8"
check "the own folder is deleted before the rebuild" logged "rm -rf '/vmfs/volumes/datastore1/nkp/nkp-cp-01'"

# 4. Destroy refuses a folder of another state.
vm_env datastore1 token-other
"$scripts/esxi-vm.sh" destroy >/dev/null 2>&1; rc=$?
check "destroy refuses a folder that belongs to another state" test "$rc" -ne 0
check "destroy leaves that folder in place" not_logged "rm -rf"

# 5. Datastore names with spaces reach scp quoted for the remote shell.
vm_env "datastore1 (1)" NO-DIR
: > "$FAKE_GETALLVMS"
"$scripts/esxi-vm.sh" create >/dev/null 2>&1
check "scp target is quoted for a datastore name with spaces" logged "scp root@192.0.2.1:'/vmfs/volumes/datastore1 (1)/nkp/nkp-cp-01/cidata.iso'"

# 6. A failed conversion leaves no file that a rerun would reuse.
export OS=ubuntu24-abc IMAGE_URL=https://example.com/img.qcow2 CACHE_DIR="$work/cache"
export BASE_VMDK="/vmfs/volumes/datastore1/nkp/images/ubuntu24-abc.vmdk" FAKE_BASE_EXISTS=1 FAKE_QEMU_RC=1
: > "$FAKE_LOG"
"$scripts/esxi-image.sh" create >/dev/null 2>&1
check "a failed conversion leaves no sparse VMDK in the cache" test ! -e "$CACHE_DIR/ubuntu24-abc-sparse.vmdk"

# 7. The base disk is imported under a temporary name and renamed when complete.
export FAKE_QEMU_RC=0
: > "$FAKE_LOG"
"$scripts/esxi-image.sh" create >/dev/null 2>&1
check "the import writes a temporary base disk" logged "'/vmfs/volumes/datastore1/nkp/images/ubuntu24-abc.tmp.vmdk' -d thin"
check "the complete base disk is renamed into place" logged "vmkfstools -E '/vmfs/volumes/datastore1/nkp/images/ubuntu24-abc.tmp.vmdk' '/vmfs/volumes/datastore1/nkp/images/ubuntu24-abc.vmdk'"

if [ "$fails" -eq 0 ]; then echo "esxi scripts: all checks passed"; else echo "esxi scripts: $fails check(s) failed"; exit 1; fi
