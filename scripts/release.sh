#!/bin/bash
# Builds a release zip of Aikon.app.
#
# Why it copies the repo somewhere else first: SwiftPM bakes the absolute path
# of the build directory into the binary (the generated resource-bundle
# accessor keeps it as a fallback lookup). Building straight from a checkout
# under /Users/<name> ships that name inside the app, where anyone can read it
# with `strings`. Building from a neutral directory leaves a path that says
# nothing about the machine.
#
# Usage: bash scripts/release.sh [version]   e.g. bash scripts/release.sh 0.1.0
set -euo pipefail

VERSION="${1:-0.1.0}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /private/tmp/aikon-release.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# Only committed files, so nothing local sneaks into a release.
git -C "$REPO" archive HEAD | tar -x -C "$WORK"

cd "$WORK"
bash scripts/bundle.sh

ZIP="$REPO/Aikon-v$VERSION.zip"
rm -f "$ZIP"
# ditto, not zip: it preserves the bundle structure and permissions macOS needs.
ditto -c -k --keepParent build/Aikon.app "$ZIP"

echo "built: $ZIP"
if strings "$WORK/build/Aikon.app/Contents/MacOS/Aikon" | grep -q "$HOME"; then
    echo "warning: the binary still mentions $HOME — check the build directory" >&2
fi
