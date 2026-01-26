# MacSnap

**Windows-style window snapping for macOS.** Instantly snap windows to halves, quarters, or fullscreen using simple keyboard shortcuts.

[![Download](https://img.shields.io/badge/Download-MacSnap.dmg-blue?style=for-the-badge)](https://github.com/domgordon/macsnap/releases/latest/download/MacSnap.dmg)
[![Latest Release](https://img.shields.io/github/v/release/domgordon/macsnap?style=flat-square)](https://github.com/domgordon/macsnap/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-12.0+-black?style=flat-square&logo=apple)](https://github.com/domgordon/macsnap)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

---

## Features

- **Snap to halves** — Left, right, top, bottom
- **Snap to quarters** — All four corners
- **Maximize** — Fill the entire screen
- **Multi-monitor** — Move windows between displays
- **Menu bar app** — Runs silently, no dock icon
- **Auto-updates** — Get new versions automatically via Sparkle
- **Launch at login** — Start with your Mac

---

## Installation

### Download (Recommended)

1. **[Download MacSnap.dmg](https://github.com/domgordon/macsnap/releases/latest/download/MacSnap.dmg)**
2. Open the DMG and drag MacSnap to Applications
3. Launch MacSnap from Applications
4. Grant Accessibility permissions when prompted
5. Done! Use the keyboard shortcuts below

### Homebrew (Coming Soon)

```bash
brew install --cask macsnap
```

---

## Keyboard Shortcuts

All shortcuts use **Control + Option (⌃⌥)** as the base modifier.

### Snap to Halves

| Shortcut | Action |
|----------|--------|
| `⌃⌥ ←` | Left half |
| `⌃⌥ →` | Right half |
| `⌃⌥ ↑` | Top half |
| `⌃⌥ ↓` | Bottom half |
| `⌃⌥ Return` | Maximize |

### Snap to Quarters

| Shortcut | Action |
|----------|--------|
| `⌃⌥⌘ ←` | Top-left quarter |
| `⌃⌥⌘ →` | Top-right quarter |
| `⌃⌥⌘⇧ ←` | Bottom-left quarter |
| `⌃⌥⌘⇧ →` | Bottom-right quarter |

### Multi-Monitor

| Shortcut | Action |
|----------|--------|
| `⌃⌥⇧ ←` | Move to left monitor |
| `⌃⌥⇧ →` | Move to right monitor |

---

## Permissions

MacSnap requires **Accessibility permissions** to control windows.

On first launch, you'll be prompted to grant access:

**System Settings → Privacy & Security → Accessibility → MacSnap ✓**

---

## Menu Bar

MacSnap lives in your menu bar. Click the icon to:

- See current version
- Check for updates
- View keyboard shortcuts
- Enable/disable snapping
- Toggle launch at login
- Access settings

---

## Requirements

- macOS 12.0 (Monterey) or later
- Accessibility permissions

---

## Building from Source

### Prerequisites

- Xcode 14+
- macOS 12.0+

### Build

```bash
# Clone the repo
git clone https://github.com/domgordon/macsnap.git
cd macsnap

# Build Release
xcodebuild -project MacSnap.xcodeproj -scheme MacSnap -configuration Release build
```

The app will be at `build/Release/MacSnap.app`

### Development

```bash
# Open in Xcode
open MacSnap.xcodeproj

# Build and Run (⌘R)
```

---

## Project Structure

```
MacSnap/
├── Sources/
│   ├── MacSnapApp.swift           # App entry point
│   ├── AppDelegate.swift          # Lifecycle management
│   ├── StatusBarController.swift  # Menu bar UI
│   ├── UpdateController.swift     # Sparkle auto-updates
│   ├── HotkeyManager.swift        # Keyboard shortcuts
│   ├── WindowManager.swift        # Window control (Accessibility)
│   ├── ScreenManager.swift        # Multi-monitor support
│   └── SnapPosition.swift         # Position calculations
├── Info.plist
└── MacSnap.entitlements
```

---

## Contributing

Contributions welcome! Please open an issue first to discuss changes.

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

<p align="center">
  Made with ❤️ for the Mac
</p>
