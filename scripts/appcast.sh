#!/bin/sh
# Writes the update feed Nook checks: one item for this release, its disk image signed with the update key
# in this Mac's keychain. Upload the result to the release as appcast.xml; Nook reads the latest release's.
# Usage: scripts/appcast.sh <notes.txt> [app] [dmg] [download URL] > appcast.xml
# Notes: one change per line, each starting with "- ". The app and disk image default to release.sh's.
set -eu
cd "$(dirname "$0")/.."

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

[ $# -ge 1 ] || fail "Usage: scripts/appcast.sh <notes.txt> [app] [dmg] [download URL]"
notes=$1
release_dir="$PWD/build/release"
app=${2:-$release_dir/DerivedData/Build/Products/Release/Nook.app}
plist="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")
dmg=${3:-$release_dir/Nook-$version.dmg}
url=${4:-https://github.com/sanvithreddyy/nook/releases/download/v$version/Nook-$version.dmg}
[ -f "$notes" ] || fail "No notes at $notes."
[ -f "$dmg" ] || fail "No disk image at $dmg; run scripts/release.sh first."

# Sparkle's signing tool comes with the package; NOOK_SIGN_UPDATE points elsewhere, NOOK_ED_KEY_FILE
# signs with a key file instead of the keychain (tests only).
sign_update=${NOOK_SIGN_UPDATE:-$release_dir/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update}
[ -x "$sign_update" ] || fail "No sign_update at $sign_update."
if [ -n "${NOOK_ED_KEY_FILE:-}" ]; then
    attributes=$("$sign_update" --ed-key-file "$NOOK_ED_KEY_FILE" "$dmg")
else
    attributes=$("$sign_update" "$dmg")
fi
case "$attributes" in
    *sparkle:edSignature=*length=*) ;;
    *) fail "sign_update didn't sign $dmg: $attributes" ;;
esac
date=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Nook</title>
    <item>
      <title>Nook $version</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <description sparkle:format="plain-text"><![CDATA[
$(cat "$notes")
]]></description>
      <enclosure url="$url" type="application/octet-stream" $attributes/>
    </item>
  </channel>
</rss>
EOF
