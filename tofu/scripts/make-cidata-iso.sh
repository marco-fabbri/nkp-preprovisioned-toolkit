#!/usr/bin/env bash
# Builds a NoCloud seed ISO (volume label "cidata") from a directory holding
# user-data, meta-data and network-config. Used by tofu/esxi and tofu/vsphere.
# Usage: make-cidata-iso.sh <source_dir> <output.iso>
set -euo pipefail
src="$1"; out="$2"
for f in user-data meta-data network-config; do
  [ -f "$src/$f" ] || { echo "missing $src/$f" >&2; exit 1; }
done
rm -f "$out"
if command -v hdiutil >/dev/null 2>&1; then
  hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata -o "$out" "$src"
elif command -v xorriso >/dev/null 2>&1; then
  xorriso -as mkisofs -quiet -volid cidata -joliet -rock -o "$out" "$src"
else
  genisoimage -quiet -volid cidata -joliet -rock -o "$out" "$src"
fi
