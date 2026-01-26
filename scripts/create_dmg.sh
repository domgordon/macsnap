#!/bin/bash
#
# create_dmg.sh - Create a styled DMG installer with Applications folder shortcut
#
# This script creates a professional macOS DMG installer that shows the
# "drag to Applications folder" experience users expect.
#
# Prerequisites:
#   - brew install create-dmg
#   - Notarized MacSnap.app (from Xcode export)
#
# Usage:
#   ./scripts/create_dmg.sh /path/to/MacSnap.app [output-name]
#
# Examples:
#   ./scripts/create_dmg.sh ~/Desktop/MacSnap-Export/MacSnap.app
#   ./scripts/create_dmg.sh ~/Desktop/MacSnap.app MacSnap-1.0.2
#
# Output:
#   Creates MacSnap.dmg (or specified name) in the current directory
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ $# -lt 1 ]; then
    echo "Usage: $0 <path-to-MacSnap.app> [output-name]"
    echo ""
    echo "Examples:"
    echo "  $0 ~/Desktop/MacSnap-Export/MacSnap.app"
    echo "  $0 ~/Desktop/MacSnap.app MacSnap-1.0.2"
    echo ""
    echo "This will create a DMG with the 'drag to Applications' experience."
    exit 1
fi

APP_PATH="$1"
OUTPUT_NAME="${2:-MacSnap}"
OUTPUT_DIR="${3:-.}"
OUTPUT_DMG="$OUTPUT_DIR/${OUTPUT_NAME}.dmg"

# Verify app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}ERROR: App not found: $APP_PATH${NC}"
    exit 1
fi

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo -e "${RED}ERROR: 'create-dmg' is not installed.${NC}"
    echo ""
    echo "Install it with Homebrew:"
    echo "  brew install create-dmg"
    echo ""
    exit 1
fi

echo "=== Creating DMG Installer ==="
echo ""
echo "App:     $APP_PATH"
echo "Output:  $OUTPUT_DMG"
echo ""

# Remove existing DMG if present
if [ -f "$OUTPUT_DMG" ]; then
    echo "Removing existing DMG..."
    rm "$OUTPUT_DMG"
fi

# Check if we have a custom background
BACKGROUND_ARG=""
BACKGROUND_PATH="$SCRIPT_DIR/dmg-background.png"
if [ -f "$BACKGROUND_PATH" ]; then
    echo "Using custom background: $BACKGROUND_PATH"
    BACKGROUND_ARG="--background $BACKGROUND_PATH"
else
    echo -e "${YELLOW}Note: No custom background found at $BACKGROUND_PATH${NC}"
    echo "      DMG will use default appearance."
fi

# Create the DMG
echo ""
echo "Creating DMG..."
echo ""

# Build the create-dmg command
# The --app-drop-link creates the Applications folder shortcut
if [ -n "$BACKGROUND_ARG" ]; then
    create-dmg \
        --volname "MacSnap" \
        --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "MacSnap.app" 150 185 \
        --hide-extension "MacSnap.app" \
        --app-drop-link 450 185 \
        $BACKGROUND_ARG \
        "$OUTPUT_DMG" \
        "$APP_PATH"
else
    create-dmg \
        --volname "MacSnap" \
        --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "MacSnap.app" 150 185 \
        --hide-extension "MacSnap.app" \
        --app-drop-link 450 185 \
        "$OUTPUT_DMG" \
        "$APP_PATH"
fi

echo ""
echo -e "${GREEN}=== Done ===${NC}"
echo ""
echo "Created: $OUTPUT_DMG"
echo ""
echo "Next steps:"
echo "  1. Test the DMG by mounting it and dragging the app"
echo "  2. Upload to GitHub Release"
echo "  3. The landing page links to: MacSnap.dmg"
echo ""
