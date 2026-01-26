import AppKit
import Sparkle

/// Manages Sparkle auto-updates for the application
/// Only active in Release builds to avoid dev builds triggering updates
final class UpdateController: NSObject {
    
    static let shared = UpdateController()
    
    #if !DEBUG
    private let updaterController: SPUStandardUpdaterController
    #endif
    
    private override init() {
        #if !DEBUG
        // Initialize Sparkle updater - starts automatically checking for updates
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
        super.init()
    }
    
    // MARK: - Public API
    
    /// The underlying Sparkle updater (only available in Release builds)
    #if !DEBUG
    var updater: SPUUpdater {
        updaterController.updater
    }
    #endif
    
    /// Check for updates in the background (non-interactive)
    /// Call this at app startup to auto-update before first run experience
    func checkForUpdatesInBackground() {
        #if !DEBUG
        updaterController.updater.checkForUpdatesInBackground()
        #endif
    }
    
    /// Manually check for updates (shows UI)
    /// Called from "Check for Updates..." menu item
    @objc func checkForUpdates(_ sender: Any?) {
        #if !DEBUG
        updaterController.checkForUpdates(sender)
        #endif
    }
    
    /// Whether the updater can check for updates
    var canCheckForUpdates: Bool {
        #if !DEBUG
        return updaterController.updater.canCheckForUpdates
        #else
        return false
        #endif
    }
}
