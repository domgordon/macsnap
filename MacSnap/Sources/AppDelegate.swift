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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("AppDelegate: Starting up...")
        
        // Check accessibility permissions
        let hasPerms = windowManager.hasAccessibilityPermissions
        debugLog("AppDelegate: Accessibility permissions = \(hasPerms)")
        
        // Initialize status bar first (so user can see the app with loading state)
        debugLog("AppDelegate: Creating StatusBarController...")
        statusBarController = StatusBarController()
        
        // Auto-enable snapping (will work if permissions are granted)
        debugLog("AppDelegate: Auto-enabling snapping...")
        hotkeyManager.start()
        
        // Mark initialization complete - stops the loading animation
        statusBarController?.markReady()
        
        // Show onboarding on first launch
        if onboardingManager.isFirstLaunch {
            debugLog("AppDelegate: First launch detected, showing onboarding...")
            showOnboarding()
        } else if !hasPerms {
            // Not first launch but missing permissions - prompt quietly
            debugLog("AppDelegate: Requesting accessibility permissions...")
            windowManager.requestAccessibilityPermissions()
        }
        
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
