#!/usr/bin/env bash
# Everything that can be verified without a phone attached.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 1/2 swift test =="
# --disable-sandbox: SwiftPM's own sandbox cannot start in restricted shells.
swift test --disable-sandbox

echo
echo "== 2/2 build the whole app for the device (unsigned) =="
# Includes the SwiftUI views, the App Intent and the widget extension, which is the part
# `swift test` cannot reach.
#
# OTHER_SWIFT_FLAGS=-disable-sandbox is what lets swift-plugin-server (SwiftUI macro
# expansion) start inside a sandboxed terminal; without it every @State errors out with
# "produced malformed response". Harmless to leave on.
# CODE_SIGNING_ALLOWED=NO keeps this machine-independent: no Apple ID, no device needed.
mkdir -p .build/tmp
TMPDIR="$PWD/.build/tmp" xcodebuild \
  -project ChessSense.xcodeproj -scheme ChessSense \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/dd-generic \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS='-disable-sandbox' \
  SWIFT_USE_INTEGRATED_DRIVER=NO \
  build

echo
echo "OK: tests green, app + widget extension compile for arm64 device."
