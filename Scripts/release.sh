#!/bin/sh
# Builds the release artefacts and refuses to continue if the version in the
# source, the tag you are cutting, and the built bundle disagree.
#
#   ./Scripts/release.sh v0.1.1
set -eu

tag=${1:?"usage: release.sh <tag, e.g. v0.1.1>"}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

version=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/BiumCore/Localization.swift)
[ "v$version" = "$tag" ] || {
  echo "버전이 어긋납니다: 소스는 $version, 태그는 $tag" >&2
  exit 1
}

swift run bium-tests
swift build -c release --triple arm64-apple-macosx --product bium
swift build -c release --triple x86_64-apple-macosx --product bium
mkdir -p dist
lipo -create -output dist/bium \
  .build/arm64-apple-macosx/release/bium \
  .build/x86_64-apple-macosx/release/bium
codesign --force --sign - dist/bium

built=$(./dist/bium --version | awk '{print $2}')
[ "$built" = "$version" ] || { echo "빌드된 바이너리가 $built 를 보고합니다" >&2; exit 1; }

./Scripts/build-app.sh
( cd dist && tar -czf "bium-$version-macos-universal.tar.gz" bium )
ditto -c -k --sequesterRsrc --keepParent dist/Bium.app dist/Bium.app.zip

echo
echo "완성:"
echo "  dist/bium-$version-macos-universal.tar.gz  $(shasum -a 256 "dist/bium-$version-macos-universal.tar.gz" | cut -d' ' -f1)"
echo "  dist/Bium.app.zip                          $(shasum -a 256 dist/Bium.app.zip | cut -d' ' -f1)"
