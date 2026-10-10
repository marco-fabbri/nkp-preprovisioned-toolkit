#!/usr/bin/env bash
# Checks the local-tool checks of ./deploy.sh tofu-* with a PATH that holds a
# fake tofu and only the system tools deploy.sh needs, never qemu-img, python3
# or curl: plan and apply of the VMware modules must stop and name what to
# install; init and destroy must still reach OpenTofu.
# Usage: tofu/scripts/tests/deploy-tools-test.sh
set -uo pipefail
repo="$(cd "$(dirname "$0")/../../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
for t in bash sh env dirname basename cat grep sed awk tr cut head tail mktemp uname readlink ls; do
  p="$(command -v "$t")" && ln -s "$p" "$work/bin/$t"
done
printf '#!/bin/sh\necho "fake tofu $*"\n' > "$work/bin/tofu"
chmod +x "$work/bin/tofu"
fails=0
run() { (cd "$work" && env -i HOME="$HOME" PATH="$work/bin" TOFU_PROVIDER="$1" "$repo/deploy.sh" "$2" 2>&1); }
check() { if "${@:2}"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails + 1)); fi; }

out="$(run esxi tofu-plan)"; rc=$?
check "esxi plan stops without qemu-img" test "$rc" -eq 127
check "esxi plan names qemu-img" grep -q "qemu-img" <<<"$out"
check "esxi plan names curl" grep -q "curl" <<<"$out"
out="$(run vsphere tofu-apply)"; rc=$?
check "vsphere apply stops without python3" grep -q "python3" <<<"$out"
out="$(run esxi tofu-destroy)"; rc=$?
check "esxi destroy reaches OpenTofu without the build tools" grep -q "fake tofu destroy" <<<"$out"
out="$(run vsphere tofu-init)"; rc=$?
check "vsphere init reaches OpenTofu without the build tools" grep -q "fake tofu init" <<<"$out"
out="$(run nutanix tofu-plan)"; rc=$?
check "nutanix plan needs no build tool" grep -q "fake tofu plan" <<<"$out"

if [ "$fails" -eq 0 ]; then echo "deploy.sh tool checks: all checks passed"; else echo "deploy.sh tool checks: $fails check(s) failed"; exit 1; fi
