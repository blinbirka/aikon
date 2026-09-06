#!/bin/bash
# Assembles build/Aikon.app from a release build.
#
# Usage: bash scripts/bundle.sh [version]      e.g. bash scripts/bundle.sh 0.1.1
set -euo pipefail

VERSION="${1:-0.1.0}"
APP="build/Aikon.app"

# Universal by default so the app runs on Intel Macs too. If this toolchain has
# no x86_64 SDK, fall back to a native build rather than failing the release.
PRODUCTS=".build/apple/Products/Release"
if swift build -c release --arch arm64 --arch x86_64; then
    :
else
    echo "note: universal build unavailable, building for this machine only" >&2
    swift build -c release
    PRODUCTS=".build/release"
fi
[ -x "$PRODUCTS/Aikon" ] || PRODUCTS=".build/release"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/Aikon" "$APP/Contents/MacOS/"

# Contents/Resources, not the bundle root. SwiftPM's generated accessor looks
# at Bundle.main.resourceURL first, which is exactly Contents/Resources for an
# .app -- and it is the only place codesign will accept, since anything loose
# in the bundle root is "unsealed contents" and fails a strict verify.
for bundle in "$PRODUCTS"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Aikon</string>
  <key>CFBundleIdentifier</key><string>io.github.blinbirka.aikon</string>
  <key>CFBundleName</key><string>Aikon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST

# Sign LAST, after every file is in place. Swift's toolchain ad-hoc signs the
# bare executable during linking; copying the icon, Info.plist and resource
# bundle in afterwards invalidates that signature, and macOS then refuses the
# app with "Aikon is damaged and can't be opened" -- which no amount of
# right-click-Open or `xattr -cr` can clear. Re-signing the finished bundle is
# what makes a downloaded build openable at all.
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "built: $APP ($(lipo -archs "$APP/Contents/MacOS/Aikon" 2>/dev/null || echo 'single arch'))"
