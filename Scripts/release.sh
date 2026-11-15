#!/bin/bash
# Build a signed, notarized, universal Undertone.app and zip it for distribution.
# Only the maintainer needs this; ./build.sh makes an ad hoc signed app for local use.
#
# One-time setup:
#   1. Install a "Developer ID Application" certificate in the login keychain.
#   2. Save notary credentials under a keychain profile:
#        xcrun notarytool store-credentials <profile> \
#          --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
#
# Environment:
#   UNDERTONE_SIGN_IDENTITY   certificate name; defaults to the Developer ID
#                             Application identity in the keychain
#   UNDERTONE_NOTARY_PROFILE  notarytool keychain profile (required unless
#                             SKIP_NOTARIZE=1)
#   SKIP_NOTARIZE=1           sign and zip only, to rehearse; Gatekeeper
#                             rejects the result
set -euo pipefail
cd "$(dirname "$0")/.."

DIST=.build/dist
APP=$DIST/Undertone.app

die() {
    echo "release: $*" >&2
    exit 1
}

IDENTITY=${UNDERTONE_SIGN_IDENTITY:-}
if [[ -z "$IDENTITY" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning |
        sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p')
    [[ -n "$IDENTITY" ]] || die "no Developer ID Application certificate in the keychain"
    [[ "$(printf '%s\n' "$IDENTITY" | wc -l)" -eq 1 ]] ||
        die "several Developer ID identities found; set UNDERTONE_SIGN_IDENTITY"
fi
if [[ "${SKIP_NOTARIZE:-}" != 1 ]]; then
    PROFILE=${UNDERTONE_NOTARY_PROFILE:-}
    [[ -n "$PROFILE" ]] || die "set UNDERTONE_NOTARY_PROFILE to a notarytool keychain profile"
fi

# Start from an empty folder so nothing signed by an earlier build is reused.
rm -rf "$DIST"
UNDERTONE_UNIVERSAL=1 UNDERTONE_APP="$PWD/$APP" UNDERTONE_SIGN_IDENTITY="$IDENTITY" ./build.sh

# Notarization rejects code without the hardened runtime or a secure timestamp,
# and code that still carries the debugging entitlement.
info=$(codesign -dvv "$APP" 2>&1)
grep -q '^CodeDirectory.*flags=.*runtime' <<<"$info" || die "hardened runtime is off"
grep -q '^Timestamp=' <<<"$info" || die "no secure timestamp"
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q get-task-allow; then
    die "the app carries the get-task-allow entitlement"
fi
if [[ "${SKIP_NOTARIZE:-}" != 1 ]]; then
    grep -q '^Authority=Developer ID Application' <<<"$info" ||
        die "not signed with a Developer ID Application certificate"
fi
codesign --verify --deep --strict "$APP"
[[ "$(lipo -archs "$APP/Contents/MacOS/Undertone" | tr ' ' '\n' | sort | tr '\n' ' ')" == "arm64 x86_64 " ]] ||
    die "the app is not universal"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ZIP=$DIST/Undertone-$VERSION.zip
package() {
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
}
package

if [[ "${SKIP_NOTARIZE:-}" != 1 ]]; then
    # notarytool exits 0 even when Apple rejects the upload, so read the status.
    log=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait 2>&1 | tee /dev/stderr)
    grep -q 'status: Accepted' <<<"$log" ||
        die "notarization was not accepted; run: xcrun notarytool log <id> --keychain-profile $PROFILE"
    # Staple the ticket so the app opens offline, then zip the stapled app.
    xcrun stapler staple "$APP"
    package
    spctl --assess --type execute -vv "$APP"
fi

echo "release: $ZIP"
shasum -a 256 "$ZIP"
