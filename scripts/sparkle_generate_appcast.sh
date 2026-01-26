#!/bin/bash
#
# sparkle_generate_appcast.sh - Generate/update appcast.xml from release artifacts
#
# This script uses Sparkle's generate_appcast tool to create or update the
# appcast.xml file based on ZIP files in a releases folder.
#
# Prerequisites:
#   - EdDSA keypair generated (run sparkle_keygen.sh first)
#   - Xcode with Sparkle SPM package (provides generate_appcast tool)
#   - Or: brew install sparkle
#
# Usage:
#   ./scripts/sparkle_generate_appcast.sh /path/to/releases/folder
#
# The releases folder should contain your notarized ZIP files:
#   releases/
#     MacSnap-1.0.1.zip
#     MacSnap-1.0.2.zip
#
# Output:
#   Updates docs/appcast.xml with entries for all releases
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APPCAST_OUTPUT="$PROJECT_ROOT/docs/appcast.xml"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <releases-folder>"
    echo ""
    echo "Example:"
    echo "  $0 ~/Desktop/macsnap-releases"
    echo ""
    echo "The releases folder should contain your notarized ZIP files."
    echo "The appcast will be written to: $APPCAST_OUTPUT"
    exit 1
fi

RELEASES_DIR="$1"

if [ ! -d "$RELEASES_DIR" ]; then
    echo "ERROR: Releases directory not found: $RELEASES_DIR"
    exit 1
fi

echo "=== Sparkle Appcast Generation ==="
echo ""
echo "Releases folder: $RELEASES_DIR"
echo "Output appcast:  $APPCAST_OUTPUT"
echo ""

# Find generate_appcast tool
GENERATE_APPCAST=""

if command -v generate_appcast &> /dev/null; then
    GENERATE_APPCAST="generate_appcast"
elif [ -f "/usr/local/bin/generate_appcast" ]; then
    GENERATE_APPCAST="/usr/local/bin/generate_appcast"
elif [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
    FOUND=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "generate_appcast" -type f 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        GENERATE_APPCAST="$FOUND"
    fi
fi

if [ -z "$GENERATE_APPCAST" ]; then
    echo "ERROR: Could not find 'generate_appcast' tool."
    echo ""
    echo "To install Sparkle tools, either:"
    echo "  1. Build the project in Xcode first (Sparkle package includes the tool)"
    echo "  2. Install via Homebrew: brew install sparkle"
    echo "  3. Download from: https://github.com/sparkle-project/Sparkle/releases"
    exit 1
fi

echo "Using generate_appcast at: $GENERATE_APPCAST"
echo ""

# Create docs directory if it doesn't exist
mkdir -p "$(dirname "$APPCAST_OUTPUT")"

# Generate the appcast
# The tool will:
# - Read ZIP files from the releases folder
# - Extract version info from the app bundle inside each ZIP
# - Sign each release with your EdDSA key from Keychain
# - Generate/update the appcast.xml
"$GENERATE_APPCAST" \
    --download-url-prefix "https://github.com/domgordon/macsnap/releases/download/" \
    --output "$APPCAST_OUTPUT" \
    "$RELEASES_DIR"

echo ""
echo "=== Done ==="
echo ""
echo "Appcast updated: $APPCAST_OUTPUT"
echo ""
echo "Next steps:"
echo "  1. Review the generated appcast.xml"
echo "  2. Commit and push to GitHub"
echo "  3. Create GitHub Release(s) and upload the ZIP files"
echo "  4. Verify the appcast URL works: https://domgordon.github.io/macsnap/appcast.xml"
echo ""
echo "Note: Make sure your GitHub repo has GitHub Pages enabled and set to serve from /docs"
echo ""
