import AppKit
import UserNotifications

/// Manages the menu bar status item and its menu
final class StatusBarController: NSObject {
    
    /// Shared instance for access from other parts of the app
    static var shared: StatusBarController?
    
    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager.shared
    
    /// Track previous permission state to detect changes
    private var lastKnownPermissionState: Bool = false
    
    /// Whether the app is still initializing
    private var isInitializing: Bool = true
    
    /// Timer for pulsing animation during initialization
    private var pulseTimer: Timer?
    private var pulseDirection: CGFloat = -0.05
    private var currentAlpha: CGFloat = 1.0
    
    // MARK: - Cached Menu Items (for efficient updates)
    
    private var cachedMenu: NSMenu?
    private var permissionStatusItem: NSMenuItem?
    private var snappingStatusItem: NSMenuItem?
    private var enableToggleItem: NSMenuItem?
    private var grantPermissionsItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var checkForUpdatesItem: NSMenuItem?
    
    // MARK: - Version Info
    
    /// Returns the app version string (e.g., "Version 1.0.1 (2)")
    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "MacSnap \(version) (\(build))"
    }
    
    override init() {
        super.init()
        lastKnownPermissionState = WindowManager.shared.hasAccessibilityPermissions
        setupStatusItem()
        startPulseAnimation()
    }
    
    deinit {
        stopPulseAnimation()
    }
    
    // MARK: - Setup
    
    private func setupStatusItem() {
        debugLog("StatusBarController: Setting up status item...")
        
        // Use a wider length for better highlight appearance (matches native menu bar items)
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        
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
        cachedMenu = createMenu()
        statusItem?.menu = cachedMenu
        
        debugLog("StatusBarController: Setup complete - icon should be visible in menu bar")
    }
    
    // MARK: - Initialization State
    
    /// Call this when the app has finished initializing (hotkeys started, etc.)
    func markReady() {
        guard isInitializing else { return }
        
        isInitializing = false
        stopPulseAnimation()
        updateMenuItems()
        debugLog("StatusBarController: App marked as ready")
    }
    
    // MARK: - Pulse Animation
    
    private func startPulseAnimation() {
        debugLog("StatusBarController: Starting pulse animation")
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updatePulse()
        }
    }
    
    private func stopPulseAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        
        // Reset to full opacity
        if let button = statusItem?.button {
            button.alphaValue = 1.0
        }
        debugLog("StatusBarController: Stopped pulse animation")
    }
    
    private func updatePulse() {
        guard let button = statusItem?.button else { return }
        
        currentAlpha += pulseDirection
        
        // Pulse between 0.3 and 1.0
        if currentAlpha <= 0.3 {
            currentAlpha = 0.3
            pulseDirection = 0.05
        } else if currentAlpha >= 1.0 {
            currentAlpha = 1.0
            pulseDirection = -0.05
        }
        
        button.alphaValue = currentAlpha
    }
    
    // MARK: - Highlight Animation
    
    /// Pulse a blue background highlight behind the menu bar icon (like native macOS selection)
    func flashIcon(times: Int = 5) {
        guard let button = statusItem?.button else { return }
        
        debugLog("StatusBarController: Pulsing highlight \(times) times")
        
        // Enable layer-backed view for Core Animation
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        
        // Pill-shaped corners like native macOS menu bar selection
        layer.cornerRadius = 5
        layer.masksToBounds = true
        
        let highlightColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        let clearColor = NSColor.clear.cgColor
        
        // Create a pulsing animation
        let animation = CAKeyframeAnimation(keyPath: "backgroundColor")
        
        // Build keyframe values: clear -> highlight -> clear (repeated)
        var values: [CGColor] = []
        var keyTimes: [NSNumber] = []
        
        for i in 0..<times {
            let baseTime = Double(i) / Double(times)
            let midTime = (Double(i) + 0.5) / Double(times)
            
            values.append(clearColor)
            keyTimes.append(NSNumber(value: baseTime))
            
            values.append(highlightColor)
            keyTimes.append(NSNumber(value: midTime))
        }
        // End with clear
        values.append(clearColor)
        keyTimes.append(NSNumber(value: 1.0))
        
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = Double(times) * 2.0  // 2 seconds per pulse cycle
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = true
        
        // Ensure we end with clear background
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.backgroundColor = clearColor
        }
        layer.add(animation, forKey: "pulseHighlight")
        CATransaction.commit()
    }
    
    // MARK: - Menu Creation (Initial)
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Version info header
        let versionItem = NSMenuItem(title: appVersionString, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Status Header - Permission status
        let hasPerms = WindowManager.shared.hasAccessibilityPermissions
        permissionStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        permissionStatusItem?.isEnabled = false
        menu.addItem(permissionStatusItem!)
        
        // Snapping status
        snappingStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        snappingStatusItem?.isEnabled = false
        menu.addItem(snappingStatusItem!)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open Accessibility Settings (prominent if permissions missing)
        grantPermissionsItem = NSMenuItem(
            title: "⚠️ Grant Accessibility Permissions...",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        grantPermissionsItem?.target = self
        grantPermissionsItem?.isHidden = hasPerms
        menu.addItem(grantPermissionsItem!)
        
        // Separator after grant permissions (hidden if perms granted)
        let grantSeparator = NSMenuItem.separator()
        grantSeparator.isHidden = hasPerms
        menu.addItem(grantSeparator)
        
        // Enable/Disable toggle
        enableToggleItem = NSMenuItem(
            title: "",
            action: #selector(toggleEnabled),
            keyEquivalent: "e"
        )
        enableToggleItem?.target = self
        menu.addItem(enableToggleItem!)
        
        menu.addItem(NSMenuItem.separator())
        
        // Check for Updates (only in Release builds)
        #if !DEBUG
        checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem?.target = self
        menu.addItem(checkForUpdatesItem!)
        
        menu.addItem(NSMenuItem.separator())
        #endif
        
        // Shortcuts reference submenu
        let shortcutsItem = NSMenuItem(title: "Keyboard Shortcuts", action: nil, keyEquivalent: "")
        shortcutsItem.submenu = KeyboardShortcuts.createMenu()
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
        
        // Update dynamic items with current state
        updateMenuItems()
        
        return menu
    }
    
    private func createSettingsMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Launch at Login
        launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem?.target = self
        launchAtLoginItem?.state = AppUtils.isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLoginItem!)
        
        menu.addItem(NSMenuItem.separator())
        
        // Show Welcome Screen
        let welcomeItem = NSMenuItem(
            title: "Show Welcome Screen...",
            action: #selector(showWelcomeScreen),
            keyEquivalent: ""
        )
        welcomeItem.target = self
        menu.addItem(welcomeItem)
        
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
    
    // MARK: - Menu Updates (Efficient)
    
    /// Update only the dynamic menu items instead of rebuilding the entire menu
    private func updateMenuItems() {
        let hasPerms = WindowManager.shared.hasAccessibilityPermissions
        let isActive = hotkeyManager.isEnabled
        
        // Update permission status
        let statusIcon = hasPerms ? "✓" : "✗"
        let statusText = hasPerms ? "Permissions: Granted" : "Permissions: NOT GRANTED"
        permissionStatusItem?.title = "\(statusIcon) \(statusText)"
        if !hasPerms {
            permissionStatusItem?.attributedTitle = NSAttributedString(
                string: "✗ Permissions: NOT GRANTED",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        } else {
            permissionStatusItem?.attributedTitle = nil
        }
        
        // Update snapping status
        if isInitializing {
            snappingStatusItem?.title = "◐ Snapping: Starting..."
            snappingStatusItem?.attributedTitle = NSAttributedString(
                string: "◐ Snapping: Starting...",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
        } else {
            let activeIcon = isActive ? "●" : "○"
            let activeText = isActive ? "Snapping: Active" : "Snapping: Inactive"
            snappingStatusItem?.title = "\(activeIcon) \(activeText)"
            snappingStatusItem?.attributedTitle = nil
        }
        
        // Update grant permissions visibility
        grantPermissionsItem?.isHidden = hasPerms
        
        // Update enable toggle
        enableToggleItem?.title = isInitializing ? "Starting..." : (isActive ? "Disable Snapping" : "Enable Snapping")
        enableToggleItem?.action = isInitializing ? nil : #selector(toggleEnabled)
        enableToggleItem?.keyEquivalent = isInitializing ? "" : "e"
        enableToggleItem?.isEnabled = !isInitializing
        
        // Update launch at login state
        launchAtLoginItem?.state = AppUtils.isLaunchAtLoginEnabled ? .on : .off
    }
    
    // MARK: - Actions
    
    @objc private func openAccessibilitySettings() {
        AppUtils.openAccessibilitySettings()
    }
    
    @objc private func showWelcomeScreen() {
        OnboardingWindowController.shared.showWindow()
    }
    
    @objc private func toggleEnabled() {
        hotkeyManager.toggle()
        updateMenuItems()
    }
    
    @objc private func toggleLaunchAtLogin() {
        AppUtils.toggleLaunchAtLogin()
        updateMenuItems()
    }
    
    @objc private func checkForUpdates() {
        // Bring app to foreground so update window appears on top
        NSApp.activate(ignoringOtherApps: true)
        UpdateController.shared.checkForUpdates(nil)
    }
    
    @objc private func restartApp() {
        AppUtils.restartApp()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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
        
        // Update dynamic menu items (efficient - no rebuild)
        updateMenuItems()
    }
    
    private func showNotificationAndRestart() {
        // Show notification using modern UNUserNotificationCenter
        let content = UNMutableNotificationContent()
        content.title = "MacSnap"
        content.body = "Permissions granted! Restarting to apply..."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "permissionGranted",
            content: content,
            trigger: nil  // Immediate delivery
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                debugLog("StatusBarController: Failed to show notification: \(error)")
            }
        }
        
        // Restart after a brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            AppUtils.restartApp()
        }
    }
}
