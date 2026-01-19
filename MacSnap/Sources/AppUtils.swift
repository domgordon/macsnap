import AppKit
import ServiceManagement

/// Shared utility functions for the app
enum AppUtils {
    
    // MARK: - App Lifecycle
    
    /// Restart the application
    static func restartApp() {
        debugLog("AppUtils: Restarting MacSnap...")
        
        let appURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error = error {
                debugLog("AppUtils: Failed to relaunch: \(error)")
            }
        }
        
        // Quit the current instance after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
    
    // MARK: - System Settings
    
    /// Open System Settings to Accessibility privacy pane
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Launch at Login
    
    /// Whether the app is configured to launch at login
    static var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return isLaunchAtLoginEnabledLegacy
        }
    }
    
    /// Enable or disable launch at login
    /// - Parameter enabled: Whether to enable or disable
    static func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    debugLog("AppUtils: Launch at login enabled")
                } else {
                    try SMAppService.mainApp.unregister()
                    debugLog("AppUtils: Launch at login disabled")
                }
            } catch {
                debugLog("AppUtils: Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            }
        } else {
            setLaunchAtLoginLegacy(enabled)
        }
    }
    
    /// Toggle launch at login state
    static func toggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginEnabled)
    }
    
    // MARK: - Legacy Launch at Login (macOS < 13)
    
    private static var isLaunchAtLoginEnabledLegacy: Bool {
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
    
    private static func setLaunchAtLoginLegacy(_ enabled: Bool) {
        guard let bundleURL = Bundle.main.bundleURL as CFURL? else { return }
        
        guard let loginItems = LSSharedFileListCreate(
            nil,
            kLSSharedFileListSessionLoginItems.takeUnretainedValue(),
            nil
        )?.takeRetainedValue() else { return }
        
        if enabled {
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
            debugLog("AppUtils: Launch at login enabled (legacy)")
        } else {
            // Remove from login items
            guard let items = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] else {
                return
            }
            for item in items {
                if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?,
                   itemURL == bundleURL as URL {
                    LSSharedFileListItemRemove(loginItems, item)
                    debugLog("AppUtils: Launch at login disabled (legacy)")
                    break
                }
            }
        }
    }
}
