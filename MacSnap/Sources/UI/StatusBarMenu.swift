import AppKit

/// Keyboard shortcuts data for the status bar menu
/// Centralized definition of all keyboard shortcuts for easy maintenance
enum KeyboardShortcuts {
    
    /// Shortcut definition with display name and key combination
    struct Shortcut {
        let name: String
        let keys: String
        
        /// Separator placeholder
        static let separator = Shortcut(name: "", keys: "")
    }
    
    /// All available keyboard shortcuts
    static let all: [Shortcut] = [
        // Half positions
        Shortcut(name: "Left Half", keys: "⌃ ⌥ ←"),
        Shortcut(name: "Right Half", keys: "⌃ ⌥ →"),
        Shortcut(name: "Top Half", keys: "⌃ ⌥ ↑"),
        Shortcut(name: "Bottom Half", keys: "⌃ ⌥ ↓"),
        Shortcut(name: "Maximize", keys: "⌃ ⌥ ↵"),
        .separator,
        // Quarter positions
        Shortcut(name: "Top Left Quarter", keys: "⌃ ⌥ ⌘ ←"),
        Shortcut(name: "Top Right Quarter", keys: "⌃ ⌥ ⌘ →"),
        Shortcut(name: "Bottom Left Quarter", keys: "⌃ ⌥ ⌘ ⇧ ←"),
        Shortcut(name: "Bottom Right Quarter", keys: "⌃ ⌥ ⌘ ⇧ →"),
        .separator,
        // Monitor movement
        Shortcut(name: "Move to Left Monitor", keys: "⌃ ⌥ ⇧ ←"),
        Shortcut(name: "Move to Right Monitor", keys: "⌃ ⌥ ⇧ →"),
    ]
    
    /// Create a menu displaying all keyboard shortcuts
    static func createMenu() -> NSMenu {
        let menu = NSMenu()
        
        for shortcut in all {
            if shortcut.name.isEmpty {
                menu.addItem(NSMenuItem.separator())
            } else {
                let item = NSMenuItem(title: "\(shortcut.name)  \(shortcut.keys)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        
        return menu
    }
}
