#!/bin/bash
# Regenerates docs/screenshot.png — the README's picture of the menu.
#
# Renders through the app's own hidden `--render-screenshot` mode (see
# `Sources/Aikon/RenderScreenshot.swift`): made-up demo projects, not
# whatever's really open on this machine, and no window or menu-bar icon
# ever appears on screen.
#
# Usage: bash scripts/make-screenshot.sh
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

OUT="docs/screenshot.png"
mkdir -p docs
.build/release/Aikon --render-screenshot "$OUT"

echo "wrote: $OUT"
