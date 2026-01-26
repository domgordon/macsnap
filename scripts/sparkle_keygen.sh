#!/bin/bash
#
# sparkle_keygen.sh - Generate EdDSA keypair for Sparkle signing
#
# This script generates an EdDSA (Ed25519) keypair for signing Sparkle updates.
# Run this ONCE during initial setup. The private key is stored in your Keychain.
#
# Prerequisites:
#   - Xcode with Sparkle SPM package (provides generate_keys tool)
#   - Or: brew install sparkle (provides /usr/local/bin/generate_keys)
#
# Usage:
#   ./scripts/sparkle_keygen.sh
#
# Output:
#   - Private key: Stored in macOS Keychain (automatic)
#   - Public key: Printed to console - copy this to Info.plist SUPublicEDKey
#

set -euo pipefail

echo "=== Sparkle EdDSA Key Generation ==="
echo ""

# Find generate_keys tool
GENERATE_KEYS=""

# Check common locations
if command -v generate_keys &> /dev/null; then
    GENERATE_KEYS="generate_keys"
elif [ -f "/usr/local/bin/generate_keys" ]; then
    GENERATE_KEYS="/usr/local/bin/generate_keys"
elif [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
    # Search in Xcode DerivedData for Sparkle's generate_keys
    FOUND=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "generate_keys" -type f 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        GENERATE_KEYS="$FOUND"
    fi
fi

if [ -z "$GENERATE_KEYS" ]; then
    echo "ERROR: Could not find 'generate_keys' tool."
    echo ""
    echo "To install Sparkle tools, either:"
    echo "  1. Build the project in Xcode first (Sparkle package includes the tool)"
    echo "  2. Install via Homebrew: brew install sparkle"
    echo "  3. Download from: https://github.com/sparkle-project/Sparkle/releases"
    echo ""
    echo "After installing, the tool should be at:"
    echo "  - /usr/local/bin/generate_keys (Homebrew)"
    echo "  - ~/Library/Developer/Xcode/DerivedData/.../generate_keys (Xcode)"
    exit 1
fi

echo "Found generate_keys at: $GENERATE_KEYS"
echo ""
echo "Generating EdDSA keypair..."
echo ""
echo "IMPORTANT: The private key will be stored in your macOS Keychain."
echo "           The public key will be printed below - add it to Info.plist"
echo ""

# Run generate_keys
"$GENERATE_KEYS"

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Copy the public key printed above"
echo "2. Open MacSnap/Info.plist"
echo "3. Replace YOUR_PUBLIC_ED25519_KEY_HERE with the public key"
echo "4. Commit the updated Info.plist"
echo ""
echo "The private key is securely stored in your Keychain and will be used"
echo "automatically when running generate_appcast or sign_update."
echo ""
