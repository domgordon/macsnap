import AppKit

/// Simple file logger for debugging
func debugLog(_ message: String) {
    let logFile = "/tmp/macsnap_debug.log"
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(timestamp)] \(message)\n"
    
    if let handle = FileHandle(forWritingAtPath: logFile) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        // Create file if it doesn't exist
        try? line.write(toFile: logFile, atomically: true, encoding: .utf8)
    }
}

/// Application delegate handling lifecycle and initialization
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusBarController: StatusBarController?
    private let windowManager = WindowManager.shared
    private let hotkeyManager = HotkeyManager.shared
    private let onboardingManager = OnboardingManager.shared
    private let updateController = UpdateController.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("AppDelegate: Starting up...")
        
        // Check for updates (doesn't require permissions)
        debugLog("AppDelegate: Checking for updates in background...")
        updateController.checkForUpdatesInBackground()
        
        // Initialize status bar (doesn't require permissions)
        debugLog("AppDelegate: Creating StatusBarController...")
        statusBarController = StatusBarController()
        
        // On first launch: show onboarding FIRST, before requesting any permissions
        // This ensures users understand WHY they need to grant accessibility access
        if onboardingManager.isFirstLaunch {
            debugLog("AppDelegate: First launch - showing onboarding before requesting permissions...")
            statusBarController?.markReady()
            showOnboarding()
            // Don't start hotkey manager yet - will happen after restart when permissions granted
            return
        }
        
        // Not first launch: check permissions and start normally
        let hasPerms = windowManager.hasAccessibilityPermissions
        debugLog("AppDelegate: Accessibility permissions = \(hasPerms)")
        
        if hasPerms {
            debugLog("AppDelegate: Starting hotkey manager...")
            hotkeyManager.start()
        } else {
            debugLog("AppDelegate: Requesting accessibility permissions...")
            windowManager.requestAccessibilityPermissions()
        }
        
        statusBarController?.markReady()
        debugLog("AppDelegate: Ready! Snapping is \(hotkeyManager.isEnabled ? "enabled" : "disabled")")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
        print("MacSnap: Shutting down")
    }
    
    // MARK: - Onboarding
    
    private func showOnboarding() {
        OnboardingWindowController.shared.showWindow()
    }
}
