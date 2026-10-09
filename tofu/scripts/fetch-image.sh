#!/usr/bin/env bash
# Downloads a cloud image once into the local cache and prints its path.
# Usage: fetch-image.sh <url> <cache_dir> <name>
set -euo pipefail
url="$1"; cache="$2"; name="$3"
mkdir -p "$cache"
img="$cache/$name.qcow2"
if [ ! -s "$img" ]; then
  curl -fsSL --retry 3 -o "$img.part" "$url"
  mv "$img.part" "$img"
fi
printf '%s\n' "$img"
