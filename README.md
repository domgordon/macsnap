# MacSnap

Windows-style window snapping for macOS. Use keyboard shortcuts to snap windows to halves, quarters, and move between monitors.

## Features

- Snap windows to left/right/top/bottom halves
- Snap windows to corners (quarters)
- Maximize windows
- Move windows between multiple monitors
- Runs silently in the menu bar
- Launch at login option

## Keyboard Shortcuts

All shortcuts use **Control + Option (⌃ + ⌥)** as the base modifier. This avoids conflicts with text editor shortcuts.

### Basic Snapping
| Shortcut | Action |
|----------|--------|
| ⌃ + ⌥ + ← | Snap to left half |
| ⌃ + ⌥ + → | Snap to right half |
| ⌃ + ⌥ + ↑ | Snap to top half |
| ⌃ + ⌥ + ↓ | Snap to bottom half |
| ⌃ + ⌥ + Return | Maximize window |

### Quarter Snapping
| Shortcut | Action |
|----------|--------|
| ⌃ + ⌥ + ⌘ + ← | Top-left quarter |
| ⌃ + ⌥ + ⌘ + → | Top-right quarter |
| ⌃ + ⌥ + ⌘ + ⇧ + ← | Bottom-left quarter |
| ⌃ + ⌥ + ⌘ + ⇧ + → | Bottom-right quarter |

### Multi-Monitor
| Shortcut | Action |
|----------|--------|
| ⌃ + ⌥ + ⇧ + ← | Move to left monitor |
| ⌃ + ⌥ + ⇧ + → | Move to right monitor |

## Requirements

- macOS 12.0 (Monterey) or later
- Xcode 14+ (for building)
- Accessibility permissions (prompted on first launch)

## Building

### Using Xcode

1. Open `MacSnap.xcodeproj` in Xcode
2. Select the MacSnap scheme
3. Build and Run (⌘R)

### Using Command Line

```bash
xcodebuild -project MacSnap.xcodeproj -scheme MacSnap -configuration Release build
```

The built app will be in `build/Release/MacSnap.app`.

## Installation

1. Build the app (see above)
2. Move `MacSnap.app` to `/Applications`
3. Launch MacSnap
4. Grant Accessibility permissions when prompted
5. (Optional) Enable "Launch at Login" from the menu bar icon

## Permissions

MacSnap requires **Accessibility permissions** to move and resize windows from other applications. On first launch, you'll be prompted to grant access in:

**System Preferences → Security & Privacy → Privacy → Accessibility**

After granting permission, you may need to restart the app.

## Menu Bar

MacSnap runs as a menu bar app with a small icon. Click it to:

- Enable/disable snapping
- View keyboard shortcuts
- Toggle Launch at Login
- Quit the app

## Architecture

```
MacSnap/
├── Sources/
│   ├── MacSnapApp.swift          # App entry point
│   ├── AppDelegate.swift         # Lifecycle and permissions
│   ├── StatusBarController.swift # Menu bar UI
│   ├── HotkeyManager.swift       # Keyboard shortcut handling
│   ├── WindowManager.swift       # Window manipulation (Accessibility APIs)
│   ├── ScreenManager.swift       # Multi-monitor support
│   └── SnapPosition.swift        # Snap position definitions
├── Info.plist                    # App configuration (LSUIElement)
└── MacSnap.entitlements          # Security entitlements
```

## License

MIT License - feel free to modify and distribute.
