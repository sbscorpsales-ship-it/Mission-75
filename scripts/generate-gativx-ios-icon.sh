#!/usr/bin/env bash
set -euo pipefail
ICON_DIR="ios/GATIVX/Assets.xcassets/AppIcon.appiconset"
command -v rsvg-convert >/dev/null 2>&1 || { echo "rsvg-convert is required (install librsvg)"; exit 1; }
rsvg-convert --width 1024 --height 1024 "$ICON_DIR/AppIcon.svg" --output "$ICON_DIR/AppIcon.png"
file "$ICON_DIR/AppIcon.png"
