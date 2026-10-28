#!/bin/zsh
# Builds a Developer ID-signed, notarized and stapled Arcadia-<version>.dmg in build/release.
#
# Notarization credentials, one of:
#   NOTARY_PROFILE=<name>                 a profile saved with `xcrun notarytool store-credentials`
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER   an App Store Connect API key (used by CI)
# Set SKIP_NOTARIZATION=1 to only build and sign.
#
# Then writes the Sparkle appcast, build/release/appcast.xml (see scripts/appcast.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:-43THU6L26P}"
IDENTITY="Developer ID Application"
VERSION=$(sed -nE 's/^ *MARKETING_VERSION: "(.*)"/\1/p' project.yml | head -1)
OUT=build/release
DMG="$OUT/Arcadia-$VERSION.dmg"

echo "▸ Arcadia $VERSION"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "▸ Archiving"
xcodebuild -project Arcadia.xcodeproj -scheme Arcadia -configuration Release \
  -archivePath "$OUT/Arcadia.xcarchive" -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" -quiet archive

echo "▸ Exporting"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$IDENTITY</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Arcadia.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" -quiet
APP="$OUT/export/Arcadia.app"
codesign --verify --deep --strict --verbose=1 "$APP"

echo "▸ Making the disk image"
mkdir -p "$OUT/dmg"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "Arcadia" -srcfolder "$OUT/dmg" -ov -format UDZO -quiet "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ "${SKIP_NOTARIZATION:-0}" == 1 ]]; then
  echo "▸ Skipping notarization"
else
  echo "▸ Notarizing"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    credentials=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    credentials=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  else
    echo "Set NOTARY_PROFILE or NOTARY_KEY_PATH/NOTARY_KEY_ID/NOTARY_ISSUER (or SKIP_NOTARIZATION=1)." >&2
    exit 1
  fi
  xcrun notarytool submit "$DMG" "${credentials[@]}" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

echo "▸ Making the appcast"
scripts/appcast.sh "$DMG" "$APP" "$OUT/appcast.xml"
echo "▸ Done: $DMG, $OUT/appcast.xml"
