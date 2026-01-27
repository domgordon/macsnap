import AppKit
import ApplicationServices

/// Information about a window for the snap assist picker
struct WindowInfo {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let frame: CGRect  // In NSScreen coordinates
    let appIcon: NSImage?  // Captured at creation time for performance
}

/// Manages window manipulation using macOS Accessibility APIs.
/// Simplified to focus on core window operations, using shared utilities for:
/// - Coordinate conversion (CoordinateConverter)
/// - Frame matching (FrameMatcher)
/// - Window list caching (WindowListCache)
/// - Animation (WindowAnimator)
final class WindowManager {
    
    static let shared = WindowManager()
    
    private let screenManager = ScreenManager.shared
    
    // MARK: - Pre-Snap Frame Cache
    
    /// Cached frame with timestamp for LRU eviction
    private struct CachedFrame {
        let frame: CGRect
        let timestamp: Date
    }
    
    /// Stores pre-snap window frames by process ID, used to restore windows to their original size
    /// Uses LRU-style cache with maximum entries and expiry time to prevent unbounded growth
    private var preSnapFrames: [pid_t: CachedFrame] = [:]
    
    /// Maximum number of cached pre-snap frames
    private let maxCachedFrames = 20
    
    /// Time after which cached frames expire (10 minutes)
    private let frameExpiry: TimeInterval = 600
    
    private init() {}
    
    /// Cleanup old and excess cached frames
    private func cleanupOldFrames() {
        let now = Date()
        
        // Remove expired entries
        preSnapFrames = preSnapFrames.filter {
            now.timeIntervalSince($0.value.timestamp) < frameExpiry
        }
        
        // If still over limit, remove oldest entries
        if preSnapFrames.count > maxCachedFrames {
            let sorted = preSnapFrames.sorted { $0.value.timestamp < $1.value.timestamp }
            let toRemove = sorted.prefix(preSnapFrames.count - maxCachedFrames)
            for (pid, _) in toRemove {
                preSnapFrames.removeValue(forKey: pid)
            }
        }
    }
    
    // MARK: - Accessibility Permissions
    
    /// Check if the app has accessibility permissions
    var hasAccessibilityPermissions: Bool {
        AXIsProcessTrusted()
    }
    
    /// Prompt user to grant accessibility permissions if not already granted
    /// - Returns: true if permissions are already granted
    @discardableResult
    func requestAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Snap Assist State Handling
    
    /// Actions for handling snap assist state before window operations
    private enum AssistAction {
        case blockIfShowing  // Block operation if picker is showing, cancel pending
        case cancelPending   // Just cancel any pending assist timer
        case dismiss         // Dismiss any showing picker and cancel pending
    }
    
    /// Handle snap assist state before a window operation
    /// - Parameter action: The action to take
    /// - Returns: true if the operation should proceed, false if blocked
    private func handleAssistState(_ action: AssistAction) -> Bool {
        switch action {
        case .blockIfShowing:
            if SnapAssistController.shared.isShowingAssist {
                debugLog("WindowManager: Operation blocked - assist overlay is showing")
                return false
            }
            SnapAssistController.shared.cancelPendingAssist()
            return true
        case .cancelPending:
            SnapAssistController.shared.cancelPendingAssist()
            return true
        case .dismiss:
            SnapAssistController.shared.dismiss()
            return true
        }
    }
    
    // MARK: - Window Operations
    
    /// Snap the frontmost window to the specified position
    /// - Parameter position: The target snap position
    /// - Returns: true if successful
    @discardableResult
    func snapFrontmostWindow(to position: SnapPosition) -> Bool {
        guard handleAssistState(.blockIfShowing) else { return false }
        
        // Get all frontmost window details in a single operation (avoids redundant AX calls)
        guard let details = WindowDiscovery.getFrontmostWindowWithDetails() else {
            debugLog("WindowManager: No frontmost window found")
            return false
        }
        
        let window = details.window
        let windowFrame = details.frame
        let frontWindowID = details.windowID
        
        let screen = screenManager.screen(for: windowFrame)
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        
        // Save pre-snap frame if window is not already snapped (for middle state restoration)
        if let pid = frontmostAppPID, detectCurrentSnapPosition() == nil {
            cleanupOldFrames()
            preSnapFrames[pid] = CachedFrame(frame: windowFrame, timestamp: Date())
            debugLog("WindowManager: Saved pre-snap frame for PID \(pid): \(windowFrame)")
        }
        
        let targetFrame = position.frame(in: visibleFrame, fullFrame: fullFrame)
        debugLog("WindowManager: Target frame for \(position): \(targetFrame)")
        
        // Animate the transition using the frame-synchronized animator
        WindowAnimator.shared.animate(window: window, from: windowFrame, to: targetFrame)
        
        // Schedule snap assist for half-screen snaps or quarter snaps (cancellable delay)
        if position.oppositeHalf != nil || position.siblingQuarter != nil {
            SnapAssistController.shared.scheduleAssist(
                for: position,
                on: screen,
                excludingWindowID: frontWindowID
            )
        }
        
        return true
    }
    
    /// Move the frontmost window to an adjacent monitor
    /// - Parameter direction: Direction to move (left or right)
    /// - Returns: true if successful
    @discardableResult
    func moveFrontmostWindow(to direction: MonitorDirection) -> Bool {
        _ = handleAssistState(.cancelPending)
        
        guard let window = getFrontmostWindow() else {
            debugLog("WindowManager: No frontmost window found")
            return false
        }
        
        guard let windowFrame = getWindowFrame(window) else {
            debugLog("WindowManager: Could not get window frame")
            return false
        }
        
        let currentScreen = screenManager.screen(for: windowFrame)
        
        guard let targetScreen = screenManager.adjacentScreen(from: currentScreen, direction: direction) else {
            debugLog("WindowManager: No adjacent screen in direction \(direction)")
            return false
        }
        
        let newFrame = screenManager.translateFrame(windowFrame, from: currentScreen, to: targetScreen)
        WindowAnimator.shared.animate(window: window, from: windowFrame, to: newFrame)
        return true
    }
    
    /// Unsnap the frontmost window to a centered "middle" state
    /// Restores the window's pre-snap size if available, otherwise uses a centered half-width fallback
    /// - Returns: true if successful
    @discardableResult
    func unsnapToMiddle() -> Bool {
        _ = handleAssistState(.dismiss)
        
        guard let window = getFrontmostWindow() else {
            debugLog("WindowManager: No frontmost window found")
            return false
        }
        
        guard let windowFrame = getWindowFrame(window) else {
            debugLog("WindowManager: Could not get window frame")
            return false
        }
        
        let screen = screenManager.screen(for: windowFrame)
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        
        // Calculate usable area (respecting menu bar and dock)
        let menuBarHeight = fullFrame.maxY - visibleFrame.maxY
        let dockHeight = visibleFrame.minY - fullFrame.minY
        let dockLeftWidth = visibleFrame.minX - fullFrame.minX
        let dockRightWidth = fullFrame.maxX - visibleFrame.maxX
        
        let usableX = fullFrame.origin.x + dockLeftWidth
        let usableY = fullFrame.origin.y + dockHeight
        let usableWidth = fullFrame.width - dockLeftWidth - dockRightWidth
        let usableHeight = fullFrame.height - menuBarHeight - dockHeight
        
        let targetFrame: CGRect
        
        if let pid = frontmostAppPID, let cached = preSnapFrames[pid] {
            // Restore saved size, centered horizontally on screen
            let savedFrame = cached.frame
            let centeredX = usableX + (usableWidth - savedFrame.width) / 2
            targetFrame = CGRect(
                x: centeredX,
                y: savedFrame.origin.y,
                width: savedFrame.width,
                height: savedFrame.height
            )
            // Clear the saved frame since we're restoring it
            preSnapFrames.removeValue(forKey: pid)
            debugLog("WindowManager: Restoring pre-snap frame for PID \(pid), centered at \(targetFrame)")
        } else {
            // Fallback: centered half-width, full height
            let halfWidth = usableWidth / 2
            let centeredX = usableX + (usableWidth - halfWidth) / 2
            targetFrame = CGRect(
                x: centeredX,
                y: usableY,
                width: halfWidth,
                height: usableHeight
            )
            debugLog("WindowManager: Using fallback center-half frame: \(targetFrame)")
        }
        
        // Animate the transition
        WindowAnimator.shared.animate(window: window, from: windowFrame, to: targetFrame)
        return true
    }
    
    /// Minimize the frontmost window to the dock
    /// - Returns: true if successful
    @discardableResult
    func minimizeFrontmostWindow() -> Bool {
        _ = handleAssistState(.dismiss)
        
        guard let window = getFrontmostWindow() else {
            debugLog("WindowManager: No frontmost window to minimize")
            return false
        }
        
        // Set the minimized attribute to true
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        debugLog("WindowManager: Minimize result: \(result.rawValue)")
        return result == .success
    }
    
    // MARK: - Snap Assist Support
    
    /// Get the process ID of the frontmost application
    var frontmostAppPID: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
    
    /// Get the CGWindowID of the frontmost window by matching its AX frame against the window list
    /// - Returns: The CGWindowID if found, nil otherwise
    func getFrontmostWindowID() -> CGWindowID? {
        WindowDiscovery.getFrontmostWindowID()
    }
    
    /// Get all visible windows except the specified window and any clean-snapped windows
    /// - Parameter excludeWindowID: Window ID to exclude (the window that was just snapped)
    /// - Parameter screen: The screen to get windows for
    /// - Returns: Array of WindowInfo for eligible windows
    func getOtherWindows(excludingWindowID excludeWindowID: CGWindowID?, on screen: NSScreen) -> [WindowInfo] {
        WindowDiscovery.getVisibleWindows(on: screen, excluding: excludeWindowID)
    }
    
    /// Snap a specific window to a position using its stored frame for matching
    /// - Parameters:
    ///   - windowID: The CGWindowID of the window (for logging only)
    ///   - ownerPID: The process ID that owns the window
    ///   - storedFrame: The frame of the window when it was captured (in NSScreen coords)
    ///   - position: The target snap position
    /// - Returns: true if successful
    @discardableResult
    func snapWindow(windowID: CGWindowID, ownerPID: pid_t, storedFrame: CGRect, to position: SnapPosition) -> Bool {
        debugLog("WindowManager: Looking for window at stored frame \(storedFrame)")
        
        // Find the window by its stored frame
        guard let axWindow = WindowDiscovery.findWindow(withFrame: storedFrame, ownerPID: ownerPID) else {
            debugLog("WindowManager: Could not find matching AX window for stored frame \(storedFrame)")
            return false
        }
        
        // Raise window to front and activate the app
        AXHelpers.raise(axWindow)
        NSRunningApplication(processIdentifier: ownerPID)?.activate(options: [.activateIgnoringOtherApps])
        
        // Get current frame and calculate target
        guard let startFrame = AXHelpers.getFrameInNSCoordinates(axWindow) else {
            debugLog("WindowManager: Could not get window frame")
            return false
        }
        
        let screen = screenManager.screen(for: startFrame)
        let targetFrame = position.frame(in: screen.visibleFrame, fullFrame: screen.frame)
        
        // Animate the window into place
        WindowAnimator.shared.animate(window: axWindow, from: startFrame, to: targetFrame)
        
        debugLog("WindowManager: Snapping window \(windowID) from \(startFrame) to \(targetFrame)")
        return true
    }
    
    // MARK: - Snap State Detection
    
    /// Detect the current snap position of the frontmost window
    /// - Returns: The matching SnapPosition if the window is snapped, nil if unsnapped
    func detectCurrentSnapPosition() -> SnapPosition? {
        guard let window = getFrontmostWindow(),
              let windowFrame = getWindowFrame(window) else {
            return nil
        }
        
        let screen = screenManager.screen(for: windowFrame)
        let result = FrameMatcher.detectSnapPosition(for: windowFrame, on: screen)
        
        if let position = result {
            debugLog("WindowManager: Detected current snap position: \(position)")
        } else {
            debugLog("WindowManager: Window is unsnapped (no matching position)")
        }
        
        return result
    }
    
    // MARK: - Private Helpers (delegating to WindowDiscovery and AXHelpers)
    
    /// Get the frontmost window of the frontmost application
    private func getFrontmostWindow() -> AXUIElement? {
        WindowDiscovery.getFrontmostWindow()
    }
    
    /// Get the current frame of a window in NSScreen coordinates
    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        AXHelpers.getFrameInNSCoordinates(window)
    }
}
