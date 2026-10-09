#!/usr/bin/env bash
# Checks tofu/scripts/build-ova.sh on a tiny image: the OVA must hold the OVF
# first, and the OVF must declare the virtual size of the source image (not the
# size of its file), or vCenter would deploy a disk too small for the OS.
# Usage: tofu/scripts/tests/build-ova-test.sh   (needs qemu-img and xmllint)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
qemu-img create -q -f qcow2 "$work/src.qcow2" 1G
# An extended attribute on the source, as macOS sets on downloaded files.
if command -v xattr >/dev/null 2>&1; then
  xattr -w com.example.test 1 "$work/src.qcow2" 2>/dev/null || true
fi
"$here/../build-ova.sh" "$work/src.qcow2" test-image ubuntu64Guest "$work/out.ova"
# Listed with Python's tar reader, as the vSphere provider (Go) reads it: the
# OVA must hold exactly the OVF and the disk, OVF first. macOS tar would add
# AppleDouble "._*" entries for files with extended attributes, and the
# provider takes the first entry ending in .ovf.
members="$(python3 -c 'import sys, tarfile; print(" ".join(m.name for m in tarfile.open(sys.argv[1]).getmembers()))' "$work/out.ova")"
[ "$members" = "test-image.ovf test-image-disk1.vmdk" ] || { echo "FAIL: OVA members are: $members"; exit 1; }
tar -xOf "$work/out.ova" test-image.ovf > "$work/test.ovf"
xmllint --noout "$work/test.ovf"
grep -q 'ovf:capacity="1073741824"' "$work/test.ovf" || { echo "FAIL: capacity is $(grep -o 'ovf:capacity="[0-9]*"' "$work/test.ovf")"; exit 1; }
grep -q 'vmw:osType="ubuntu64Guest"' "$work/test.ovf" || { echo "FAIL: osType missing"; exit 1; }
echo "build-ova: OVF first, capacity 1 GiB, osType set"
