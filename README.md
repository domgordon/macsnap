# MacSnap

**Window snapping for macOS.** Instantly snap windows to halves, quarters, or fullscreen using simple keyboard shortcuts.

[![Download](https://img.shields.io/badge/Download-MacSnap.dmg-blue?style=for-the-badge)](https://macsnap.vercel.app)
[![Latest Release](https://img.shields.io/github/v/release/domgordon/macsnap?style=flat-square)](https://github.com/domgordon/macsnap/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-12.0+-black?style=flat-square&logo=apple)](https://github.com/domgordon/macsnap)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

---

## Features

- **Snap to halves** — Left, right, top, bottom
- **Snap to quarters** — All four corners
- **Maximize** — Fill the entire screen
- **Smart layout** — After snapping, pick another window to fill the rest
- **Menu bar app** — Runs silently, no dock icon
- **Auto-updates** — Get new versions automatically via Sparkle
- **Launch at login** — Start with your Mac

---

## Installation

**[Download from macsnap.vercel.app](https://macsnap.vercel.app)**

1. Download the DMG
2. Drag MacSnap to Applications
3. Launch and grant Accessibility permissions
4. Done!

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
git clone https://github.com/domgordon/macsnap.git
cd macsnap
xcodebuild -project MacSnap.xcodeproj -scheme MacSnap -configuration Release build
```

The app will be at `build/Release/MacSnap.app`

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

## License

MIT License - see [LICENSE](LICENSE) for details.
