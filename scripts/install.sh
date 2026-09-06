#!/bin/bash
# Builds Aikon and installs it into /Applications.
#
# This script does not turn on login-at-startup or the session-status hook —
# the app switches those on itself, from its own Settings window
# (Sources/Aikon/HookInstaller.swift, Sources/Aikon/LoginItem.swift). That
# way it works the same whether you built from source or just downloaded a
# ready-made .app with no repo or scripts at all.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "error: $1" >&2
    exit 1
}

# --- Preflight ---------------------------------------------------------

macos_version="$(sw_vers -productVersion 2>/dev/null || true)"
[ -n "$macos_version" ] || fail "could not determine the macOS version (sw_vers failed)"
macos_major="${macos_version%%.*}"
if ! [[ "$macos_major" =~ ^[0-9]+$ ]] || [ "$macos_major" -lt 14 ]; then
    fail "macOS 14 or newer is required (found $macos_version) — update macOS and try again"
fi

xcode-select -p >/dev/null 2>&1 || \
    fail "Xcode command line tools are required — install them with: xcode-select --install"

swift_version_line="$(swift --version 2>/dev/null | head -1 || true)"
[ -n "$swift_version_line" ] || fail "Swift toolchain not found — install Xcode or the Swift toolchain from swift.org"
swift_major="$(printf '%s' "$swift_version_line" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)"
if ! [[ "$swift_major" =~ ^[0-9]+$ ]] || [ "$swift_major" -lt 6 ]; then
    fail "Swift 6 or newer is required (found: $swift_version_line) — this package needs swift-tools-version 6.0"
fi

# --- Build and install ---------------------------------------------------

bash scripts/bundle.sh

DEST="/Applications/Aikon.app"

pkill -f "Aikon.app/Contents/MacOS/Aikon" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
cp -R build/Aikon.app "$DEST"

codesign --verify --deep --strict "$DEST" || \
    fail "the installed app at $DEST failed codesign verification — do not run it, please file an issue"

echo "installed: $DEST"
echo "Turn on login-at-startup and the session-status hook from inside the app: Settings."
echo "Aikon has no Dock icon — look for it in the menu bar."
