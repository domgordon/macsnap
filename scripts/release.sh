#!/bin/bash
#
# release.sh - One-command release automation for MacSnap
#
# Usage:
#   ./scripts/release.sh 1.0.2        # Release specific version
#   ./scripts/release.sh patch        # Auto-bump patch (1.0.1 -> 1.0.2)
#   ./scripts/release.sh minor        # Auto-bump minor (1.0.1 -> 1.1.0)
#   ./scripts/release.sh major        # Auto-bump major (1.0.1 -> 2.0.0)
#
# What it does:
#   1. Bumps version in Xcode project
#   2. Builds Release archive
#   3. Notarizes with Apple (requires one-time credential setup)
#   4. Creates ZIP (for Sparkle updates)
#   5. Creates DMG (for website downloads)
#   6. Updates appcast.xml
#   7. Deploys to Vercel
#   8. Creates GitHub Release with assets
#   9. Commits and pushes changes
#
# One-time setup required:
#   1. Store notarization credentials:
#      xcrun notarytool store-credentials "MacSnap-Notarize" \
#        --apple-id "your@email.com" \
#        --team-id "AGK96TCFNU" \
#        --password "app-specific-password"
#
#   2. Install GitHub CLI: brew install gh
#   3. Login to GitHub: gh auth login
#   4. Install create-dmg: brew install create-dmg
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="MacSnap"
SCHEME="MacSnap"
BUNDLE_ID="com.dom.macsnap"

# Directories
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export"
RELEASES_DIR="$BUILD_DIR/releases"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_step() { echo -e "${BLUE}==>${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Get current version from project
get_current_version() {
    grep -m1 "MARKETING_VERSION" "$PROJECT_ROOT/MacSnap.xcodeproj/project.pbxproj" | sed 's/.*= //' | tr -d ';' | tr -d ' '
}

get_current_build() {
    grep -m1 "CURRENT_PROJECT_VERSION" "$PROJECT_ROOT/MacSnap.xcodeproj/project.pbxproj" | sed 's/.*= //' | tr -d ';' | tr -d ' '
}

# Bump version
bump_version() {
    local current="$1"
    local bump_type="$2"
    
    IFS='.' read -r major minor patch <<< "$current"
    
    case "$bump_type" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "$major.$((minor + 1)).0" ;;
        patch) echo "$major.$minor.$((patch + 1))" ;;
        *) echo "$bump_type" ;;  # Assume it's a specific version
    esac
}

# Update version in project.pbxproj
set_version() {
    local new_version="$1"
    local new_build="$2"
    
    # Update MARKETING_VERSION
    sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $new_version;/g" \
        "$PROJECT_ROOT/MacSnap.xcodeproj/project.pbxproj"
    
    # Update CURRENT_PROJECT_VERSION
    sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $new_build;/g" \
        "$PROJECT_ROOT/MacSnap.xcodeproj/project.pbxproj"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing=()
    
    if ! command -v xcrun &> /dev/null; then
        missing+=("Xcode Command Line Tools")
    fi
    
    if ! command -v gh &> /dev/null; then
        missing+=("GitHub CLI (brew install gh)")
    fi
    
    if ! command -v create-dmg &> /dev/null; then
        missing+=("create-dmg (brew install create-dmg)")
    fi
    
    if ! xcrun notarytool history --keychain-profile "MacSnap-Notarize" &> /dev/null; then
        missing+=("Notarization credentials (see script header for setup)")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing prerequisites:"
        for item in "${missing[@]}"; do
            echo "  - $item"
        done
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Main release function
do_release() {
    local version_arg="${1:-patch}"
    
    cd "$PROJECT_ROOT"
    
    # Determine version
    local current_version=$(get_current_version)
    local current_build=$(get_current_build)
    local new_version=$(bump_version "$current_version" "$version_arg")
    local new_build=$((current_build + 1))
    
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║         MacSnap Release Automation         ║"
    echo "╠════════════════════════════════════════════╣"
    echo "║  Current: $current_version ($current_build)                        ║"
    echo "║  New:     $new_version ($new_build)                        ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    
    read -p "Proceed with release? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    check_prerequisites
    
    # Clean build directory
    log_step "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR" "$RELEASES_DIR"
    log_success "Build directory ready"
    
    # Step 1: Bump version
    log_step "Bumping version to $new_version ($new_build)..."
    set_version "$new_version" "$new_build"
    log_success "Version updated"
    
    # Step 2: Build archive
    log_step "Building Release archive..."
    xcodebuild archive \
        -project "$PROJECT_ROOT/MacSnap.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -quiet
    log_success "Archive built"
    
    # Step 3: Export with Developer ID
    log_step "Exporting with Developer ID signing..."
    
    # Create export options plist
    cat > "$BUILD_DIR/ExportOptions.plist" << 'EXPORTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EXPORTEOF
    
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
        -quiet
    log_success "App exported"
    
    # Step 4: Notarize
    log_step "Submitting for notarization (this may take a few minutes)..."
    
    # Create ZIP for notarization
    ditto -c -k --keepParent "$EXPORT_PATH/$PROJECT_NAME.app" "$BUILD_DIR/$PROJECT_NAME-notarize.zip"
    
    xcrun notarytool submit "$BUILD_DIR/$PROJECT_NAME-notarize.zip" \
        --keychain-profile "MacSnap-Notarize" \
        --wait
    
    # Staple the notarization ticket
    xcrun stapler staple "$EXPORT_PATH/$PROJECT_NAME.app"
    log_success "App notarized and stapled"
    
    # Step 5: Create release artifacts
    log_step "Creating release artifacts..."
    
    # ZIP for Sparkle
    local zip_name="$PROJECT_NAME-$new_version.zip"
    ditto -c -k --keepParent "$EXPORT_PATH/$PROJECT_NAME.app" "$RELEASES_DIR/$zip_name"
    log_success "Created $zip_name"
    
    # DMG for website (kept separate from releases folder)
    local dmg_name="$PROJECT_NAME.dmg"
    "$SCRIPT_DIR/create_dmg.sh" "$EXPORT_PATH/$PROJECT_NAME.app" "$PROJECT_NAME" "$BUILD_DIR"
    log_success "Created $dmg_name"
    
    # Step 6: Update appcast
    log_step "Updating appcast..."
    "$SCRIPT_DIR/sparkle_generate_appcast.sh" "$RELEASES_DIR"
    log_success "Appcast updated"
    
    # Step 7: Deploy to Vercel
    log_step "Deploying to Vercel..."
    cd "$PROJECT_ROOT/website"
    npx vercel --prod --yes > /dev/null 2>&1
    cd "$PROJECT_ROOT"
    log_success "Website deployed"
    
    # Step 8: Commit changes
    log_step "Committing changes..."
    git add -A
    git commit -m "Release MacSnap $new_version"
    git tag "v$new_version"
    git push
    git push --tags
    log_success "Changes committed and pushed"
    
    # Step 9: Create GitHub Release
    log_step "Creating GitHub Release..."
    gh release create "v$new_version" \
        --title "MacSnap $new_version" \
        --notes "MacSnap version $new_version" \
        "$RELEASES_DIR/$zip_name" \
        "$BUILD_DIR/$dmg_name"
    log_success "GitHub Release created"
    
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║            Release Complete! 🎉            ║"
    echo "╠════════════════════════════════════════════╣"
    echo "║  Version: $new_version ($new_build)                        ║"
    echo "║  GitHub:  https://github.com/domgordon/macsnap/releases/tag/v$new_version"
    echo "║  Appcast: https://macsnap.vercel.app/appcast.xml"
    echo "╚════════════════════════════════════════════╝"
    echo ""
}

# Run it
do_release "$@"
