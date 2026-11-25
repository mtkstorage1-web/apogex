#!/bin/bash
# Build build/ios/Tminus.ipa.  Usage: tools/build_ios_ipa.sh [signed|unsigned]
#  signed   : needs an iPad registered to your Apple team (connected once via Xcode) -> xcodebuild archive+export
#  unsigned : (default) Payload-packaged .ipa for Xcode re-sign / sideload tools
# Exports a Godot pack and builds the Xcode project from the iOS template.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-unsigned}"
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
VER=$("$GODOT" --version | cut -d. -f1-3).stable
TPL="$HOME/Library/Application Support/Godot/export_templates/$VER/ios.zip"
TEAM=$(grep -m1 app_store_team_id export_presets.cfg | cut -d'"' -f2)
BUNDLE=$(grep -m1 bundle_identifier export_presets.cfg | cut -d'"' -f2)
OUT=build/ios; XC=$OUT/xcode
[ -f "$TPL" ] || { echo "Missing $TPL (download Godot_v${VER%.stable}-stable_export_templates.tpz)"; exit 1; }
mkdir -p "$OUT"
PACK_DIR=$(mktemp -d "$PWD/$OUT/.pack.XXXXXX")
trap 'rm -rf "$PACK_DIR"' EXIT
"$GODOT" --headless --path . --export-pack iOS "$PACK_DIR/Tminus.pck"
[ -s "$PACK_DIR/Tminus.pck" ] || { echo "Godot did not produce Tminus.pck" >&2; exit 1; }
mv "$PACK_DIR/Tminus.pck" "$OUT/Tminus.pck"
python3 tools/make_ios_xcodeproj.py "$TPL" "$OUT/Tminus.pck" "$XC" "$TEAM" "$BUNDLE" release
rm -rf "$OUT/Payload" "$OUT/Tminus.ipa"
if [ "$MODE" = signed ]; then
  xcodebuild -project "$XC/Tminus.xcodeproj" -scheme Tminus -configuration Release -sdk iphoneos \
    -archivePath "$OUT/Tminus.xcarchive" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" archive
  printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>method</key><string>development</string><key>teamID</key><string>%s</string></dict></plist>' "$TEAM" > "$OUT/exportOptions.plist"
  xcodebuild -exportArchive -archivePath "$OUT/Tminus.xcarchive" -exportOptionsPlist "$OUT/exportOptions.plist" -exportPath "$OUT/export" -allowProvisioningUpdates
  cp "$OUT"/export/*.ipa "$OUT/Tminus.ipa"
else
  xcodebuild -project "$XC/Tminus.xcodeproj" -scheme Tminus -configuration Release -sdk iphoneos \
    -derivedDataPath "$OUT/dd" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
  mkdir "$OUT/Payload"; cp -R "$OUT"/dd/Build/Products/Release-iphoneos/Tminus.app "$OUT/Payload/"
  (cd "$OUT" && zip -qry Tminus.ipa Payload)
fi
echo "IPA: $PWD/$OUT/Tminus.ipa"
