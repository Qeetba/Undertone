#!/bin/bash
# Build a standalone, ad-hoc signed macOS app. Never installs or changes defaults.
#
# Environment (all optional; Scripts/release.sh sets them):
#   UNDERTONE_UNIVERSAL=1    build for Apple silicon and Intel instead of this Mac only
#   UNDERTONE_APP            where to assemble the app; defaults to dist/Undertone.app
#   UNDERTONE_SIGN_IDENTITY  sign with this certificate, the hardened runtime and a
#                            secure timestamp instead of ad hoc
set -euo pipefail
cd "$(dirname "$0")"
ARCHS=""
if [[ -n "${UNDERTONE_UNIVERSAL:-}" ]]; then ARCHS="--arch arm64 --arch x86_64"; fi
# shellcheck disable=SC2086 # ARCHS is a list of flags
swift build -c release $ARCHS
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCHS --show-bin-path)/Undertone"

if [[ "${1:-}" == "--render-preview" ]]; then
    "$BIN" --render-preview "${2:?Provide an output PNG path}" "${@:3}"
    exit 0
fi

APP="${UNDERTONE_APP:-$PWD/dist/Undertone.app}"
[[ "$APP" == *.app ]] || { echo "build: UNDERTONE_APP must end in .app" >&2; exit 2; }
mkdir -p "$(dirname "$APP")"
# Only replace our generated app, not the rest of its folder.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Undertone"
cp Resources/Info.plist "$APP/Contents/Info.plist"
ICONSET="$(mktemp -d)/Undertone.iconset"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT
swift Scripts/generate-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Undertone.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"
if [[ -n "${UNDERTONE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$UNDERTONE_SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - --timestamp=none "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"
echo "Built: $APP"
