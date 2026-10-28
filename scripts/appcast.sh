#!/bin/zsh
# Writes a signed Sparkle appcast for a release disk image:
#   scripts/appcast.sh <Arcadia-<version>.dmg> <Arcadia.app> <appcast.xml>
#
# The disk image is signed with the EdDSA key that Sparkle's generate_keys saved in the login
# keychain (macOS asks once to let sign_update use it), or with SPARKLE_PRIVATE_KEY when set
# (CI; the key exported with `generate_keys -x`). SIGN_UPDATE overrides the sign_update tool.
# The enclosure points at the GitHub release asset, and the release notes are this version's
# section of CHANGELOG.md.
set -euo pipefail
cd "$(dirname "$0")/.."

DMG="$1"
APP="$2"
FEED="$3"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
REPO_URL="https://github.com/akkanferhan/arcadia"

# Sparkle's tools come with its Swift package, which the build resolved.
if [[ -z "${SIGN_UPDATE:-}" ]]; then
  BUILD_DIR=$(xcodebuild -project Arcadia.xcodeproj -scheme Arcadia -configuration Release -showBuildSettings 2>/dev/null \
    | sed -nE 's/^ *BUILD_DIR = (.*)/\1/p' | head -1)
  SIGN_UPDATE="${BUILD_DIR%/Build/*}/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
fi
[[ -x "$SIGN_UPDATE" ]] || { echo "Sparkle's sign_update was not found at $SIGN_UPDATE" >&2; exit 1; }
# The stapled disk image is final now; its signature covers every byte.
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  signature=$(echo "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$DMG")
else
  signature=$("$SIGN_UPDATE" "$DMG")
fi
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
MINIMUM=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")
# Release notes are this version's section of CHANGELOG.md, shown as Markdown by Sparkle.
NOTES=$(awk -v v="$VERSION" '/^## /{p = ($0 ~ "\\[" v "\\]")} p' CHANGELOG.md | tail -n +2)
cat > "$FEED" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Arcadia</title>
    <link>$REPO_URL</link>
    <item>
      <title>Arcadia $VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <link>$REPO_URL/releases/tag/v$VERSION</link>
      <description sparkle:format="markdown"><![CDATA[
$NOTES
]]></description>
      <enclosure url="$REPO_URL/releases/download/v$VERSION/Arcadia-$VERSION.dmg" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
XML
xmllint --noout "$FEED"
