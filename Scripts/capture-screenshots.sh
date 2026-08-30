#!/bin/sh
# Captures the app window once per language into docs/.
#
#   ./Scripts/capture-screenshots.sh
#
# Needs Screen Recording permission for the terminal running it: without it
# macOS hands back only the desktop, with every window omitted.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
app="$root/dist/Bium.app"
[ -d "$app" ] || { echo "먼저 ./Scripts/build-app.sh 를 실행하세요" >&2; exit 1; }
mkdir -p docs

window_id() {
  cat <<'SWIFT' > "$TMPDIR/bium-winid.swift"
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    guard (w[kCGWindowOwnerName as String] as? String)?.lowercased().contains("bium") == true else { continue }
    let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    if (bounds["Height"] as? Double ?? 0) > 400,
       let id = w[kCGWindowNumber as String] as? Int { print(id); break }
}
SWIFT
  swift "$TMPDIR/bium-winid.swift" 2>/dev/null | head -1
}

for lang in en ko; do
  echo "== $lang =="
  pkill -f 'Bium.app/Contents/MacOS/BiumApp' 2>/dev/null || true
  sleep 1

  BIUM_LANG=$lang "$app/Contents/MacOS/BiumApp" &
  pid=$!
  # The window only fills in once the first scan finishes.
  sleep 40

  id=$(window_id)
  [ -n "$id" ] || { echo "창을 찾지 못했습니다" >&2; kill "$pid" 2>/dev/null || true; exit 1; }

  screencapture -x -o -l "$id" "docs/screenshot-$lang.png" || {
    echo "캡처 실패. 시스템 설정 > 개인정보 보호 및 보안 > 화면 기록 에 터미널을 추가하세요." >&2
    kill "$pid" 2>/dev/null || true
    exit 1
  }
  # Trim to a sensible width for a README.
  sips -Z 1600 "docs/screenshot-$lang.png" >/dev/null
  kill "$pid" 2>/dev/null || true
  echo "docs/screenshot-$lang.png"
done

pkill -f 'Bium.app/Contents/MacOS/BiumApp' 2>/dev/null || true
echo "완료"
