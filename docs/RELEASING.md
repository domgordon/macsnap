# MacSnap Release Guide

## What I Do Manually

1. Bump version in Xcode (MARKETING_VERSION + CURRENT_PROJECT_VERSION)
2. Archive in Xcode → Distribute App → Developer ID → Upload (notarize) → Export
3. Create ZIP of the exported .app
4. Run `./scripts/sparkle_generate_appcast.sh ~/releases` to update appcast
5. Commit appcast.xml changes and push
6. Create GitHub Release, upload ZIP
7. Enable GitHub Pages if first release (Settings → Pages → Source: `/docs`)

---

## One-Time Setup

### 1. Generate Sparkle Signing Keys

Run once to create your EdDSA keypair:

```bash
./scripts/sparkle_keygen.sh
```

This will:
- Store the private key in your macOS Keychain (secure, automatic)
- Print the public key to the console

**Important**: Copy the public key and update `MacSnap/Info.plist`:

```xml
<key>SUPublicEDKey</key>
<string>PASTE_YOUR_PUBLIC_KEY_HERE</string>
```

Commit this change.

### 2. Enable GitHub Pages

1. Go to your repo: https://github.com/domgordon/macsnap/settings/pages
2. Under "Source", select **Deploy from a branch**
3. Select branch: `main`, folder: `/docs`
4. Save

Your appcast will be available at: `https://domgordon.github.io/macsnap/appcast.xml`

### 3. Verify Code Signing

Ensure your Xcode project has:
- **Development Team**: Set to your Apple Developer ID
- **Code Signing Identity**: "Developer ID Application"
- **Hardened Runtime**: Enabled (already set)

---

## Release Checklist

### Step 1: Bump Version

In Xcode, update the version numbers in the target build settings:

| Setting | Description | Example |
|---------|-------------|---------|
| `MARKETING_VERSION` | User-facing version (semver) | `1.0.2` |
| `CURRENT_PROJECT_VERSION` | Build number (increment each release) | `3` |

Or edit directly in `MacSnap.xcodeproj/project.pbxproj`.

### Step 2: Build Release Archive

1. In Xcode: **Product → Archive**
2. Wait for archive to complete
3. In Organizer, select the new archive
4. Click **Distribute App**
5. Select **Developer ID**
6. Select **Upload** (sends to Apple for notarization)
7. Wait for notarization (usually 5-15 minutes)
8. Once notarized, click **Export**
9. Choose export location (e.g., `~/Desktop/MacSnap-Export`)

### Step 3: Create Release ZIP

```bash
# Navigate to export folder
cd ~/Desktop/MacSnap-Export

# Create ZIP (preserving code signature)
ditto -c -k --keepParent MacSnap.app MacSnap-1.0.2.zip
```

**Important**: Use `ditto` not `zip` to preserve code signatures and extended attributes.

### Step 4: Organize Release Artifacts

Create a releases folder and add your ZIP:

```bash
mkdir -p ~/macsnap-releases
mv ~/Desktop/MacSnap-Export/MacSnap-1.0.2.zip ~/macsnap-releases/
```

Name format: `MacSnap-{version}.zip` (e.g., `MacSnap-1.0.2.zip`)

### Step 5: Generate Appcast

```bash
./scripts/sparkle_generate_appcast.sh ~/macsnap-releases
```

This will:
- Read all ZIPs in the folder
- Extract version info from each app bundle
- Sign with your EdDSA key (from Keychain)
- Update `docs/appcast.xml`

### Step 6: Review and Commit

Review the updated appcast:

```bash
git diff docs/appcast.xml
```

Commit and push:

```bash
git add docs/appcast.xml
git commit -m "Release MacSnap 1.0.2"
git push
```

### Step 7: Create GitHub Release

1. Go to https://github.com/domgordon/macsnap/releases/new
2. Create tag: `v1.0.2` (match your version)
3. Title: `MacSnap 1.0.2`
4. Description: Release notes (what changed)
5. Upload the ZIP file: `MacSnap-1.0.2.zip`
6. Publish release

### Step 8: Verify

1. Check appcast URL loads: https://domgordon.github.io/macsnap/appcast.xml
2. Verify the download URL in appcast matches your GitHub Release asset URL
3. Test update on a machine with an older version installed

---

## Troubleshooting

### "generate_appcast not found"

Install Sparkle tools via Homebrew:

```bash
brew install sparkle
```

Or build the project in Xcode first (Sparkle package includes the tools).

### Notarization Failed

Check the notarization log in Xcode Organizer for details. Common issues:
- Hardened Runtime not enabled
- Unsigned frameworks/libraries
- Entitlements issues

### Signature Verification Failed

Ensure you're using the same key that generated `SUPublicEDKey` in Info.plist:

```bash
# View your public key
./scripts/sparkle_keygen.sh
# (It will show existing key if already generated)
```

### GitHub Pages Not Working

1. Verify Pages is enabled: Settings → Pages
2. Check the source is set to `main` branch, `/docs` folder
3. Wait a few minutes for deployment
4. Check Actions tab for deployment status

---

## File Naming Convention

| File | Format | Example |
|------|--------|---------|
| ZIP artifact | `MacSnap-{version}.zip` | `MacSnap-1.0.2.zip` |
| Git tag | `v{version}` | `v1.0.2` |
| GitHub Release | `MacSnap {version}` | `MacSnap 1.0.2` |

---

## Appcast URL Structure

The appcast expects download URLs in this format:

```
https://github.com/domgordon/macsnap/releases/download/v{version}/MacSnap-{version}.zip
```

Example:
```
https://github.com/domgordon/macsnap/releases/download/v1.0.2/MacSnap-1.0.2.zip
```

The `generate_appcast` script uses `--download-url-prefix` to construct these URLs automatically based on the version extracted from the app bundle.

---

## Security Notes

- **Private Key**: Stored in macOS Keychain, never committed to git
- **Public Key**: Safe to commit (in Info.plist)
- **Notarization**: Required for apps distributed outside the App Store
- **Hardened Runtime**: Required for notarization, already enabled

---

## Quick Reference

```bash
# One-time: Generate signing keys
./scripts/sparkle_keygen.sh

# Sign a single artifact (if needed manually)
./scripts/sparkle_sign.sh ~/Desktop/MacSnap-1.0.2.zip

# Generate appcast from releases folder
./scripts/sparkle_generate_appcast.sh ~/macsnap-releases
```
