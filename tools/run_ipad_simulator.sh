#!/bin/bash
# Build Tminus for the iOS Simulator, boot an iPad simulator, install and launch. Usage: tools/run_ipad_simulator.sh [device-name-substring]
# Requires build/ios/xcode (run tools/build_ios_ipa.sh once first). Simulator slice is arm64+x86_64 (arm64 built locally, see make_ios_xcodeproj.py).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
BUNDLE="${BUNDLE:-com.apogex.tminus}"
WANT="${1:-}"
OUT=build/ios; XC=$OUT/xcode
[ -d "$XC/Tminus.xcodeproj" ] || { echo "Missing $XC/Tminus.xcodeproj. Run tools/build_ios_ipa.sh first." >&2; exit 1; }
LIST=$(xcrun simctl list devices available | grep -i 'ipad' || true)
pick() { echo "$LIST" | grep -i "$1" | head -1; }
LINE=""
for p in "$WANT" "iPad Pro 13" "iPad Pro" "iPad Air" "iPad"; do
  [ -z "$p" ] && continue
  LINE=$(pick "$p"); [ -n "$LINE" ] && break
done
[ -n "$LINE" ] || { echo "No iPad simulator available"; exit 1; }
UDID=$(echo "$LINE" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}')
echo "iPad simulator: $LINE"
PACK_DIR=$(mktemp -d "$PWD/$OUT/.pack.XXXXXX")
trap 'rm -rf "$PACK_DIR"' EXIT
"$GODOT" --headless --path . --export-pack iOS "$PACK_DIR/Tminus.pck"
[ -s "$PACK_DIR/Tminus.pck" ] || { echo "Godot did not produce Tminus.pck" >&2; exit 1; }
mv "$PACK_DIR/Tminus.pck" "$OUT/Tminus.pck"
cp "$OUT/Tminus.pck" "$XC/Tminus.pck"
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcodebuild -project "$XC/Tminus.xcodeproj" -scheme Tminus -configuration Debug -sdk iphonesimulator \
  -derivedDataPath "$OUT/sim_derived" CODE_SIGNING_ALLOWED=NO build -quiet
APP="$OUT/sim_derived/Build/Products/Debug-iphonesimulator/Tminus.app"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE"
