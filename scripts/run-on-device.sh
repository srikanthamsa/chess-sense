#!/usr/bin/env bash
# Build, install and launch on a physically connected iPhone.
#
#   ./scripts/run-on-device.sh            # build + install + launch
#   ./scripts/run-on-device.sh --check    # only report what the Mac can see
#
# Signing: the team is already in project.yml, but Xcode still needs your Apple ID added
# under Xcode > Settings > Accounts so a development profile can be created. Without that
# xcodebuild fails with "No Accounts".
set -euo pipefail
cd "$(dirname "$0")/.."

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

echo "== devices attached =="
xcrun devicectl list devices 2>/dev/null | sed -n '1,2p;/physical/p'

# Columns: Name  Identifier(UDID)  State  Model  Reality
read -r UDID NAME <<<"$(
  xcrun devicectl list devices 2>/dev/null \
  | awk '/physical/ && /iPhone/ && /available/ {
      for (i = 1; i <= NF; i++) if ($i ~ /-/) { print $i, $0; exit }
    }'
)"

if [[ -z "${UDID:-}" ]]; then
  echo
  echo "No available physical iPhone found."
  echo "  - iPhone unlocked?"
  echo "  - tapped 'Trust This Computer' on the phone?"
  echo "  - Settings > Privacy & Security > Developer Mode > On (then restart)"
  echo "  - data-capable cable / different USB port?"
  echo
  echo "Note: an iPad shows up here too, but iPads have no Dynamic Island and no Action"
  echo "Button, so the app's whole point needs the iPhone."
  exit 1
fi

echo
echo "iPhone: $NAME"
echo "UDID:   $UDID"
[[ $CHECK_ONLY -eq 1 ]] && exit 0

BUNDLE_ID="$(grep -o 'ai\.chesssense\.app[^ ]*' project.yml | head -1)"
APP_PATH=".build/dd/Build/Products/Debug-iphoneos/ChessSense.app"

echo
echo "== build =="
xcodebuild -project ChessSense.xcodeproj -scheme ChessSense \
  -destination "id=$UDID" -derivedDataPath .build/dd \
  -allowProvisioningUpdates build

echo
echo "== install =="
xcrun devicectl device install app --device "$UDID" "$APP_PATH"

echo
echo "== launch =="
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" || true

echo
echo "Done. In the app: pick a starting-position screenshot, Start Live Activity,"
echo "then bind 'Best Move' to Back Tap or the Action Button in Shortcuts."
