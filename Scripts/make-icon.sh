#!/bin/sh
# Builds Resources/AppIcon.icns from a single 1024x1024 PNG.
#
#   ./Scripts/make-icon.sh path/to/icon-1024.png
set -eu

src=${1:?"usage: make-icon.sh <1024x1024 png>"}
root=$(cd "$(dirname "$0")/.." && pwd)
set="$root/dist/AppIcon.iconset"

rm -rf "$set"; mkdir -p "$set"
for size in 16 32 128 256 512; do
  sips -z $size $size "$src" --out "$set/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$src" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$set" -o "$root/Resources/AppIcon.icns"
echo "완성: $root/Resources/AppIcon.icns"
