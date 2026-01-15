import AppKit

/// Shared utility functions for the app
enum AppUtils {
    
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
    
    /// Open System Settings to Accessibility privacy pane
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
