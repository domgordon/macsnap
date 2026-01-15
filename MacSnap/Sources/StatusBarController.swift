import AppKit
import ServiceManagement

/// Manages the menu bar status item and its menu
final class StatusBarController: NSObject {
    
    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager.shared
    
    /// Track previous permission state to detect changes
    private var lastKnownPermissionState: Bool = false
    
    override init() {
        super.init()
        lastKnownPermissionState = WindowManager.shared.hasAccessibilityPermissions
        setupStatusItem()
    }
    
    // MARK: - Setup
    
    private func setupStatusItem() {
        debugLog("StatusBarController: Setting up status item...")
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem?.button else {
            debugLog("StatusBarController: ERROR - Failed to create status bar button!")
            return
        }
        
        debugLog("StatusBarController: Button created successfully")
        
        // Use SF Symbol for the icon (available on macOS 11+)
        if let image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "MacSnap") {
            image.isTemplate = true
            button.image = image
            debugLog("StatusBarController: SF Symbol icon set")
        } else {
            // Fallback: create a simple rectangle icon
            button.title = "⊞"
            debugLog("StatusBarController: Fallback text icon set")
        }
        
        button.toolTip = "MacSnap - Window Snapping"
        statusItem?.menu = createMenu()
        
        debugLog("StatusBarController: Setup complete - icon should be visible in menu bar")
    }
    
    // MARK: - Menu Creation
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Status Header
        let hasPerms = WindowManager.shared.hasAccessibilityPermissions
        let isActive = hotkeyManager.isEnabled
        
        let statusIcon = hasPerms ? "✓" : "✗"
        let statusText = hasPerms ? "Permissions: Granted" : "Permissions: NOT GRANTED"
        let statusItem = NSMenuItem(title: "\(statusIcon) \(statusText)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        if !hasPerms {
            statusItem.attributedTitle = NSAttributedString(
                string: "✗ Permissions: NOT GRANTED",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        }
        menu.addItem(statusItem)
        
        let activeIcon = isActive ? "●" : "○"
        let activeText = isActive ? "Snapping: Active" : "Snapping: Inactive"
        let activeItem = NSMenuItem(title: "\(activeIcon) \(activeText)", action: nil, keyEquivalent: "")
        activeItem.isEnabled = false
        menu.addItem(activeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open Accessibility Settings (prominent if permissions missing)
        if !hasPerms {
            let permItem = NSMenuItem(
                title: "⚠️ Grant Accessibility Permissions...",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            permItem.target = self
            menu.addItem(permItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        // Enable/Disable toggle
        let enableItem = NSMenuItem(
            title: isActive ? "Disable Snapping" : "Enable Snapping",
            action: #selector(toggleEnabled),
            keyEquivalent: "e"
        )
        enableItem.target = self
        menu.addItem(enableItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Shortcuts reference submenu
        let shortcutsItem = NSMenuItem(title: "Keyboard Shortcuts", action: nil, keyEquivalent: "")
        shortcutsItem.submenu = createShortcutsMenu()
        menu.addItem(shortcutsItem)
        
        // Settings submenu
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = createSettingsMenu()
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Restart
        let restartItem = NSMenuItem(
            title: "Restart MacSnap",
            action: #selector(restartApp),
            keyEquivalent: "r"
        )
        restartItem.target = self
        menu.addItem(restartItem)
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit MacSnap",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Set delegate to refresh menu state
        menu.delegate = self
        
        return menu
    }
    
    private func createSettingsMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Launch at Login
        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open Accessibility Settings
        let accessItem = NSMenuItem(
            title: "Open Accessibility Settings...",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessItem.target = self
        menu.addItem(accessItem)
        
        return menu
    }
    
    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    private func createShortcutsMenu() -> NSMenu {
        let menu = NSMenu()
        
        let shortcuts: [(String, String)] = [
            ("Left Half", "⌃ ⌥ ←"),
            ("Right Half", "⌃ ⌥ →"),
            ("Top Half", "⌃ ⌥ ↑"),
            ("Bottom Half", "⌃ ⌥ ↓"),
            ("Maximize", "⌃ ⌥ ↵"),
            ("", ""),  // Separator placeholder
            ("Top Left Quarter", "⌃ ⌥ ⌘ ←"),
            ("Top Right Quarter", "⌃ ⌥ ⌘ →"),
            ("Bottom Left Quarter", "⌃ ⌥ ⌘ ⇧ ←"),
            ("Bottom Right Quarter", "⌃ ⌥ ⌘ ⇧ →"),
            ("", ""),  // Separator placeholder
            ("Move to Left Monitor", "⌃ ⌥ ⇧ ←"),
            ("Move to Right Monitor", "⌃ ⌥ ⇧ →"),
        ]
        
        for (title, shortcut) in shortcuts {
            if title.isEmpty {
                menu.addItem(NSMenuItem.separator())
            } else {
                let item = NSMenuItem(title: "\(title)  \(shortcut)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        
        return menu
    }
    
    // MARK: - Actions
    
    @objc private func toggleEnabled() {
        hotkeyManager.toggle()
        refreshMenu()
    }
    
    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if isLaunchAtLoginEnabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                print("MacSnap: Failed to toggle launch at login: \(error)")
            }
        } else {
            // Fallback for older macOS versions
            toggleLaunchAtLoginLegacy()
        }
        refreshMenu()
    }
    
    @objc private func restartApp() {
        debugLog("StatusBarController: Restarting MacSnap...")
        
        // Get the path to the current app
        let appURL = Bundle.main.bundleURL
        
        // Use NSWorkspace to relaunch
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error = error {
                debugLog("StatusBarController: Failed to relaunch: \(error)")
            }
        }
        
        // Quit the current instance after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Launch at Login
    
    private var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return isLaunchAtLoginEnabledLegacy
        }
    }
    
    // Legacy support for macOS < 13
    private var isLaunchAtLoginEnabledLegacy: Bool {
        guard let bundleURL = Bundle.main.bundleURL as CFURL? else { return false }
        
        guard let loginItems = LSSharedFileListCreate(
            nil,
            kLSSharedFileListSessionLoginItems.takeUnretainedValue(),
            nil
        )?.takeRetainedValue() else { return false }
        
        guard let items = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] else {
            return false
        }
        
        for item in items {
            if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?,
               itemURL == bundleURL as URL {
                return true
            }
        }
        return false
    }
    
    private func toggleLaunchAtLoginLegacy() {
        guard let bundleURL = Bundle.main.bundleURL as CFURL? else { return }
        
        guard let loginItems = LSSharedFileListCreate(
            nil,
            kLSSharedFileListSessionLoginItems.takeUnretainedValue(),
            nil
        )?.takeRetainedValue() else { return }
        
        if isLaunchAtLoginEnabledLegacy {
            // Remove from login items
            guard let items = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] else {
                return
            }
            for item in items {
                if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?,
                   itemURL == bundleURL as URL {
                    LSSharedFileListItemRemove(loginItems, item)
                    break
                }
            }
        } else {
            // Add to login items
            LSSharedFileListInsertItemURL(
                loginItems,
                kLSSharedFileListItemLast.takeUnretainedValue(),
                nil,
                nil,
                bundleURL,
                nil,
                nil
            )
        }
    }
    
    // MARK: - Helpers
    
    private func refreshMenu() {
        statusItem?.menu = createMenu()
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Check if permissions changed from not-granted to granted
        let currentPermissionState = WindowManager.shared.hasAccessibilityPermissions
        
        if !lastKnownPermissionState && currentPermissionState {
            // Permissions were just granted! Auto-restart
            debugLog("StatusBarController: Permissions granted! Auto-restarting...")
            showNotificationAndRestart()
            return
        }
        
        lastKnownPermissionState = currentPermissionState
        
        // Refresh menu items when opened
        refreshMenu()
    }
    
    private func showNotificationAndRestart() {
        // Show notification
        let notification = NSUserNotification()
        notification.title = "MacSnap"
        notification.informativeText = "Permissions granted! Restarting to apply..."
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
        
        // Restart after a brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.restartApp()
        }
    }
}
