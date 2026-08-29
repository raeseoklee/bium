#!/bin/sh
# Builds a release binary and puts it on PATH.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
prefix="${PREFIX:-$HOME/.local/bin}"

cd "$root"
echo "빌드 중…"
swift build -c release

mkdir -p "$prefix"
install -m 755 "$root/.build/release/bium" "$prefix/bium"
echo "설치됨: $prefix/bium"

case ":$PATH:" in
  *":$prefix:"*) ;;
  *) echo "주의: $prefix 가 PATH 에 없습니다. 셸 설정에 추가하세요:"
     echo "  export PATH=\"$prefix:\$PATH\"" ;;
esac
