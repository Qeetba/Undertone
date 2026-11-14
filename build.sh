#!/bin/bash
# Build a standalone, ad-hoc signed macOS app. Never installs or changes defaults.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Undertone"

if [[ "${1:-}" == "--render-preview" ]]; then
    "$BIN" --render-preview "${2:?Provide an output PNG path}"
    exit 0
fi

APP="$PWD/dist/Undertone.app"
mkdir -p dist
# Only replace our generated app, not the rest of dist.
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
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=1 "$APP"
echo "Built: $APP"
