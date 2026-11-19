#!/usr/bin/env bash
# Build, install and launch on a physically connected iPhone.
#
#   ./scripts/run-on-device.sh            # build + install + launch
#   ./scripts/run-on-device.sh --check    # only report what the Mac can see
#
# Signing: the team is in project.yml, but Xcode still needs your Apple ID under
# Xcode > Settings > Accounts so a development profile can be created.
set -euo pipefail
cd "$(dirname "$0")/.."

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

echo "== devices attached =="
xcrun devicectl list devices 2>/dev/null | grep -E "Name|-----|iPhone|iPad" 

# Pick a wired iPhone: a row containing "iPhone", an identifier with "UDID", that is not
# a simulator. Note the plain listing leaves the Reality column blank for real iPhones,
# so filtering on "physical" misses them — that bug cost one round trip.
UDID="$(
  xcrun devicectl list devices 2>/dev/null \
  | awk '/iPhone/ && /UDID/ && !/simulated|shutdown/ { for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-/) { print $i; exit } }'
)"

if [[ -z "${UDID:-}" ]]; then
  echo
  echo "No usable iPhone found. Check:"
  echo "  - iPhone unlocked, and 'Trust This Computer' tapped"
  echo "  - Settings > Privacy & Security > Developer Mode > On (then restart)"
  echo "  - data-capable cable / a different USB port"
  echo "  - Xcode > Settings > Accounts: your Apple ID must be added for signing"
  exit 1
fi

echo
echo "iPhone UDID: $UDID"

# Developer Mode is the single most common blocker and devicectl reports it precisely.
DETAILS="$(xcrun devicectl device info details --device "$UDID" 2>&1 || true)"
if grep -qi "Developer Mode is turned off" <<<"$DETAILS"; then
  echo
  echo "BLOCKED: Developer Mode is off on the iPhone."
  echo "  Settings > Privacy & Security > Developer Mode > On, then restart the phone."
  echo "  (Developer Mode only appears after the device has been connected once.)"
  exit 2
fi
grep -E "Device State|Transport Type|OS Version|Marketing Name" <<<"$DETAILS" | sed 's/^[[:space:]]*/  /' || true

[[ $CHECK_ONLY -eq 1 ]] && exit 0

BUNDLE_ID="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER: \(ai\.snse\.app\).*/\1/p' project.yml | head -1)"
BUNDLE_ID="${BUNDLE_ID:-ai.snse.app}"
APP_PATH=".build/dd/Build/Products/Debug-iphoneos/SNSE.app"

echo
echo "== generate =="
# project.yml is the source of truth: without this, version bumps and new files never
# reach the build, and the phone keeps reporting a stale CFBundleVersion.
if command -v xcodegen >/dev/null 2>&1; then
  TMPDIR="$(pwd)/.build/tmp" xcodegen generate | tail -1
else
  echo "xcodegen not installed; using the existing project"
fi

echo
echo "== build =="
xcodebuild -project SNSE.xcodeproj -scheme SNSE \
  -destination "id=$UDID" -derivedDataPath .build/dd \
  -allowProvisioningUpdates \
  OTHER_SWIFT_FLAGS='-disable-sandbox' \
  SWIFT_USE_INTEGRATED_DRIVER=NO \
  build

echo
echo "== install =="
xcrun devicectl device install app --device "$UDID" "$APP_PATH"

echo
echo "== launch =="
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" || true

echo
echo "Done. In the app: pick a starting-position screenshot, Start Live Activity,"
echo "then bind 'Best Move' to Back Tap or the Action Button in Shortcuts."
