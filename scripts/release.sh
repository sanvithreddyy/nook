#!/bin/sh
# Builds a signed, universal Release app and a notarized disk image.
set -eu
cd "$(dirname "$0")/.."

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

notarize=yes
case "$#:$*" in
    0:) ;;
    1:--no-notarize) notarize=no ;;
    *) fail "Usage: scripts/release.sh [--no-notarize]" ;;
esac

NOOK_SIGN_IDENTITY=${NOOK_SIGN_IDENTITY:-Developer ID Application}
NOOK_NOTARY_PROFILE=${NOOK_NOTARY_PROFILE:-nook}
NOOK_TEAM_ID=${NOOK_TEAM_ID:-}
if [ -z "$NOOK_TEAM_ID" ] && [ -f Config/Signing.local.xcconfig ]; then
    NOOK_TEAM_ID=$(awk -F= '/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=/ {
        value = $2
        sub(/\/\/.*$/, "", value)
        gsub(/[[:space:]\"]/, "", value)
        team = value
    } END { print team }' Config/Signing.local.xcconfig)
fi

# Resolve a certificate name or SHA-1 to one valid identity.
identities=$(security find-identity -v -p codesigning)
matches=$(printf '%s\n' "$identities" | awk -v requested="$NOOK_SIGN_IDENTITY" '
    /"/ {
        name = $0
        sub(/^[^"]*"/, "", name)
        sub(/".*$/, "", name)
        if ($2 == requested || name == requested || index(name, requested ": ") == 1)
            print $2 "\t" name
    }')
count=$(printf '%s\n' "$matches" | awk 'NF { count++ } END { print count+0 }')
if [ "$count" -eq 0 ]; then
    fail "Create a Developer ID Application certificate in Xcode Settings > Accounts > Manage Certificates; no valid identity matching '$NOOK_SIGN_IDENTITY' was found."
fi
[ "$count" -eq 1 ] || fail "Multiple signing identities match; set NOOK_SIGN_IDENTITY to the certificate's full name or SHA-1."
sign_hash=$(printf '%s\n' "$matches" | cut -f1)
sign_name=$(printf '%s\n' "$matches" | cut -f2-)
[ -n "$NOOK_TEAM_ID" ] || fail "Set NOOK_TEAM_ID or DEVELOPMENT_TEAM in Config/Signing.local.xcconfig."

if [ "$notarize" = yes ]; then
    if profile_check=$(xcrun notarytool history --keychain-profile "$NOOK_NOTARY_PROFILE" --output-format plist 2>&1); then
        :
    else
        case "$profile_check" in
            *"No Keychain password item found"*)
                fail "Create the notary profile '$NOOK_NOTARY_PROFILE' in Terminal with xcrun notarytool store-credentials $NOOK_NOTARY_PROFILE --apple-id <email> --team-id $NOOK_TEAM_ID --password <app-specific-password>." ;;
            *) printf '%s\n' "$profile_check" >&2
                fail "Could not validate notary profile '$NOOK_NOTARY_PROFILE'; check its credentials and network access." ;;
        esac
    fi
    case "$sign_name" in
        "Developer ID Application: "*) ;;
        *) fail "Create a Developer ID Application certificate in Xcode Settings > Accounts > Manage Certificates and select it with NOOK_SIGN_IDENTITY." ;;
    esac
fi

release_dir="$PWD/build/release"
app="$release_dir/DerivedData/Build/Products/Release/Nook.app"
mkdir -p "$release_dir"
xcodegen generate --quiet
# A plain build keeps symbols; stripping and dead-code removal make the app smaller.
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$release_dir/DerivedData" -quiet \
    DEPLOYMENT_POSTPROCESSING=YES DEAD_CODE_STRIPPING=YES \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_STYLE=Manual \
    "CODE_SIGN_IDENTITY=$sign_hash" "DEVELOPMENT_TEAM=$NOOK_TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS=--timestamp

archs=$(lipo -archs "$app/Contents/MacOS/Nook")
case "$archs" in
    *arm64*x86_64*|*x86_64*arm64*) ;;
    *) fail "The Release app is not universal (it has: $archs)." ;;
esac
codesign --verify --deep --strict --verbose=2 "$app"
sign_details=$(codesign -d --verbose=4 "$app" 2>&1)
printf '%s\n' "$sign_details"
printf '%s\n' "$sign_details" | grep -q '^CodeDirectory .*flags=.*runtime' || fail "The Release app does not have hardened runtime enabled."
printf '%s\n' "$sign_details" | grep -q '^Timestamp=' || fail "The Release app does not have a secure timestamp."
printf '%s\n' "$sign_details" | grep -Fxq "Authority=$sign_name" || fail "The Release app was signed with an unexpected identity."
printf '%s\n' "$sign_details" | grep -Fxq "TeamIdentifier=$NOOK_TEAM_ID" || fail "The Release app was signed for an unexpected team."

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
dmg="$release_dir/Nook-$version.dmg"
staging=$(mktemp -d "$release_dir/dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT
trap 'exit 1' HUP INT TERM
ditto "$app" "$staging/Nook.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Nook -srcfolder "$staging" -format UDZO -ov "$dmg"
codesign --sign "$sign_hash" --timestamp "$dmg"
codesign --verify --strict --verbose=2 "$dmg"

if [ "$notarize" = yes ]; then
    result="$release_dir/notarization.plist"
    notary_exit=0
    xcrun notarytool submit "$dmg" --keychain-profile "$NOOK_NOTARY_PROFILE" --wait \
        --output-format plist > "$result" || notary_exit=$?
    cat "$result"
    submission_id=$(/usr/libexec/PlistBuddy -c 'Print :id' "$result" 2>/dev/null || true)
    status=$(/usr/libexec/PlistBuddy -c 'Print :status' "$result" 2>/dev/null || true)
    if [ "$notary_exit" -ne 0 ] || [ "$status" != Accepted ]; then
        if [ -n "$submission_id" ]; then
            printf "Notary log: xcrun notarytool log '%s' --keychain-profile '%s'\n" "$submission_id" "$NOOK_NOTARY_PROFILE" >&2
        fi
        fail "Notarization failed; see build/release/notarization.plist and the notarytool output."
    fi
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl -a -t open --context context:primary-signature -vv "$dmg"
    spctl -a -t exec -vv "$app"
else
    printf '%s\n' 'Notarization, stapling and Gatekeeper checks skipped (--no-notarize).'
fi

printf '\nDMG: %s\nVersion: %s\n' "$dmg" "$version"
shasum -a 256 "$dmg"
