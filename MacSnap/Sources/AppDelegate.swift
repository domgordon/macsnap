import AppKit
import os.log

// MARK: - Debug Logging

/// Unified logging subsystem for MacSnap
private let logSubsystem = Bundle.main.bundleIdentifier ?? "com.macsnap"
private let logger = Logger(subsystem: logSubsystem, category: "general")

/// Debug logger using Apple's unified logging system.
/// - In DEBUG builds: Logs to unified logging (visible in Console.app) and optionally to file
/// - In RELEASE builds: No-op (completely compiled out)
///
/// View logs in Console.app by filtering for "MacSnap" or use:
/// `log stream --predicate 'subsystem == "com.macsnap"'`
func debugLog(_ message: String) {
    #if DEBUG
    // Use os.log for efficient, structured logging
    logger.debug("\(message, privacy: .public)")
    
    // Also write to file for easy access during development
    writeToLogFile(message)
    #endif
}

#if DEBUG
/// Shared file handle for efficient log file writing
private var logFileHandle: FileHandle?
private let logFilePath = "/tmp/macsnap_debug.log"
private let logQueue = DispatchQueue(label: "com.macsnap.logging", qos: .utility)

/// Write message to log file on background queue
private func writeToLogFile(_ message: String) {
    logQueue.async {
        let timestamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withTime, .withColonSeparatorInTime])
        let line = "[\(timestamp)] \(message)\n"
        
        guard let data = line.data(using: .utf8) else { return }
        
        // Create or open file handle
        if logFileHandle == nil {
            if !FileManager.default.fileExists(atPath: logFilePath) {
                FileManager.default.createFile(atPath: logFilePath, contents: nil)
            }
            logFileHandle = FileHandle(forWritingAtPath: logFilePath)
        }
        
        // Write to file
        if let handle = logFileHandle {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Fallback: recreate handle on next write
                logFileHandle = nil
            }
        }
    }
}
#endif

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
        StatusBarController.shared = statusBarController
        
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
