#!/bin/sh
# Assembles Bium.app from the SwiftPM build products.
#
# SwiftPM cannot emit an application bundle, and this project deliberately does
# not carry an Xcode project, so the bundle is put together by hand here.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/dist/Bium.app"
universal=${UNIVERSAL:-1}

cd "$root"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

if [ "$universal" = "1" ]; then
  echo "빌드 중 (arm64, x86_64)…"
  swift build -c release --triple arm64-apple-macosx --product BiumApp
  swift build -c release --triple x86_64-apple-macosx --product BiumApp
  lipo -create -output "$app/Contents/MacOS/BiumApp" \
    .build/arm64-apple-macosx/release/BiumApp \
    .build/x86_64-apple-macosx/release/BiumApp
else
  echo "빌드 중 (현재 아키텍처)…"
  swift build -c release --product BiumApp
  cp .build/release/BiumApp "$app/Contents/MacOS/BiumApp"
fi

version=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/BiumCore/Localization.swift)
[ -n "$version" ] || { echo "버전을 읽지 못했습니다"; exit 1; }
sed "s/__VERSION__/$version/g" Resources/Info.plist > "$app/Contents/Info.plist"
echo "버전 $version"
# Declaring the localizations is what makes macOS render the standard menus in
# Korean; the directories only have to exist for the language to count as
# supported.
for lang in en ko; do
  mkdir -p "$app/Contents/Resources/$lang.lproj"
  cp "Resources/$lang.lproj/InfoPlist.strings" "$app/Contents/Resources/$lang.lproj/"
done

[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns" \
  || echo "주의: Resources/AppIcon.icns 가 없어 기본 아이콘이 사용됩니다."

# Ad-hoc signature, matching how the CLI is released: it survives a copy and
# needs no developer certificate.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"

echo "완성: $app"
