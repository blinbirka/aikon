#!/bin/bash
set -euo pipefail
swift build -c release
APP="build/Aikon.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Aikon "$APP/Contents/MacOS/"

# SwiftPM's generated resource accessor looks for the resource bundle at
# Bundle.main.bundleURL/<Name>.bundle -- that is, directly inside the .app,
# not inside Contents/Resources where an Xcode-built app would keep it.
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/"
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
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
echo "built: $APP"
