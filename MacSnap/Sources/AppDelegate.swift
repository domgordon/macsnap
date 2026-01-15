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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("AppDelegate: Starting up...")
        
        // Check accessibility permissions (don't block with modal)
        let hasPerms = windowManager.hasAccessibilityPermissions
        debugLog("AppDelegate: Accessibility permissions = \(hasPerms)")
        
        // Initialize status bar first (so user can see the app)
        debugLog("AppDelegate: Creating StatusBarController...")
        statusBarController = StatusBarController()
        
        // Auto-enable snapping (will work if permissions are granted)
        debugLog("AppDelegate: Auto-enabling snapping...")
        hotkeyManager.start()
        
        // If no permissions, just request them (non-blocking) and show in menu
        if !hasPerms {
            debugLog("AppDelegate: Requesting accessibility permissions...")
            windowManager.requestAccessibilityPermissions()
        }
        
        debugLog("AppDelegate: Ready! Snapping is \(hotkeyManager.isEnabled ? "enabled" : "disabled")")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
        print("MacSnap: Shutting down")
    }
    
}
