#!/usr/bin/env bash
# Everything that can be verified without an Xcode UI session.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== swift test =="
# --disable-sandbox: SwiftPM's own sandbox can't start in restricted CI/sandbox
# environments. Harmless elsewhere; CI runs plain `swift test`.
swift test --disable-sandbox

echo "== typecheck: core + non-SwiftUI app layer (iOS 17 simulator SDK) =="
mkdir -p .build/tmp .build/mc
TMPDIR="$PWD/.build/tmp" xcrun -sdk iphonesimulator swiftc -typecheck \
  -target arm64-apple-ios17.0-simulator \
  -module-cache-path .build/mc \
  $(find Sources/ChessSenseCore -name '*.swift') \
  Shared/BestMoveAttributes.swift \
  App/CalibrationStore.swift \
  App/LiveActivityController.swift \
  App/AnalysisPipeline.swift

echo
echo "OK. The SwiftUI surface is not covered here -- build it in Xcode:"
echo "  App/ChessSenseApp.swift  App/ContentView.swift  App/AnalyzeBoardIntent.swift  Widgets/BestMoveWidgets.swift"
echo "(SwiftUI/AppIntents macros need the macro plugin host that a headless sandbox can't start.)"
