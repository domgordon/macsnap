import AppKit
import ApplicationServices

/// Information about a window for the snap assist picker
struct WindowInfo {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let frame: CGRect  // In NSScreen coordinates
    
    /// Get the app icon for this window's owner
    var appIcon: NSImage? {
        NSRunningApplication(processIdentifier: ownerPID)?.icon
    }
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
    
    /// Stores pre-snap window frames by process ID, used to restore windows to their original size
    private var preSnapFrames: [pid_t: CGRect] = [:]
    
    private init() {}
    
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
    
    // MARK: - Window Operations
    
    /// Snap the frontmost window to the specified position
    /// - Parameter position: The target snap position
    /// - Returns: true if successful
    @discardableResult
    func snapFrontmostWindow(to position: SnapPosition) -> Bool {
        // If snap assist overlay is showing, block window movement (modal lock)
        if SnapAssistController.shared.isShowingAssist {
            debugLog("WindowManager: Snap blocked - assist overlay is showing")
            return false
        }
        
        // Cancel any pending assist timer (user is still adjusting)
        SnapAssistController.shared.cancelPendingAssist()
        
        let frontPID = frontmostAppPID
        
        // Get the window ID before snapping (for picker exclusion)
        let frontWindowID = getFrontmostWindowID()
        
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
        
        // Save pre-snap frame if window is not already snapped (for middle state restoration)
        if let pid = frontPID, detectCurrentSnapPosition() == nil {
            preSnapFrames[pid] = windowFrame
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
        // Cancel any pending assist timer (changing monitors)
        SnapAssistController.shared.cancelPendingAssist()
        
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
        // Dismiss any showing picker or cancel pending timer (leaving snapped state)
        SnapAssistController.shared.dismiss()
        
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
        
        if let pid = frontmostAppPID, let savedFrame = preSnapFrames[pid] {
            // Restore saved size, centered horizontally on screen
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
        // Dismiss any showing picker or cancel pending timer
        SnapAssistController.shared.dismiss()
        
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
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        guard let window = getFrontmostWindow(),
              let axPosition = getWindowPosition(window),
              let axSize = getWindowSize(window) else {
            return nil
        }
        
        let axFrame = CGRect(origin: axPosition, size: axSize)
        let windowList = WindowListCache.shared.getWindowList()
        
        // Find matching window in CG window list
        for windowInfo in windowList {
            guard let ownerPID = WindowListCache.getOwnerPID(windowInfo),
                  ownerPID == frontApp.processIdentifier,
                  let windowID = WindowListCache.getWindowID(windowInfo),
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            
            let cgFrame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            
            if FrameMatcher.matchesExact(axFrame, cgFrame) {
                debugLog("WindowManager: Found frontmost window ID: \(windowID)")
                return windowID
            }
        }
        
        debugLog("WindowManager: Could not find frontmost window ID")
        return nil
    }
    
    /// Get all visible windows except the specified window and any clean-snapped windows
    /// - Parameter excludeWindowID: Window ID to exclude (the window that was just snapped)
    /// - Parameter screen: The screen to get windows for
    /// - Returns: Array of WindowInfo for eligible windows
    func getOtherWindows(excludingWindowID excludeWindowID: CGWindowID?, on screen: NSScreen) -> [WindowInfo] {
        let windowList = WindowListCache.shared.getWindowList()
        
        // First pass: collect basic window info
        struct WindowCandidate {
            let windowID: CGWindowID
            let ownerPID: pid_t
            let ownerName: String
            let cgTitle: String
            let cgFrame: CGRect
            let nsFrame: CGRect
        }
        
        var candidates: [WindowCandidate] = []
        
        for (currentIndex, windowInfo) in windowList.enumerated() {
            // Validate window (no PID exclusion - we filter by window ID instead)
            guard WindowListCache.isValidWindow(windowInfo, excludePID: nil, minSize: 100) else {
                continue
            }
            
            guard let windowID = WindowListCache.getWindowID(windowInfo),
                  let ownerPID = WindowListCache.getOwnerPID(windowInfo),
                  let ownerName = WindowListCache.getOwnerName(windowInfo),
                  let nsFrame = WindowListCache.getFrame(windowInfo),
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            
            // Skip the specific excluded window (the one that was just snapped)
            if let excludeID = excludeWindowID, windowID == excludeID {
                continue
            }
            
            // Build CG frame for title lookup
            let cgFrame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            
            // Check if window is on the specified screen
            let windowCenter = CGPoint(x: nsFrame.midX, y: nsFrame.midY)
            if !screen.frame.contains(windowCenter) {
                continue
            }
            
            // Skip windows that are clean-snapped AND not overlapped by higher z-order windows
            // A window is only truly "clean snapped" if it matches a snap position and is visible (not covered)
            if FrameMatcher.detectSnapPosition(for: nsFrame, on: screen) != nil {
                // Check if any higher z-order window (earlier in the list) overlaps this one
                let isOverlapped = windowList[0..<currentIndex].contains { higherWindowInfo in
                    guard WindowListCache.isValidWindow(higherWindowInfo, excludePID: nil, minSize: 100),
                          let higherFrame = WindowListCache.getFrame(higherWindowInfo) else {
                        return false
                    }
                    return higherFrame.intersects(nsFrame)
                }
                
                if !isOverlapped {
                    // Truly clean-snapped (matches position and not covered), skip it
                    debugLog("WindowManager: Skipping clean-snapped window '\(ownerName)' at \(nsFrame)")
                    continue
                }
                // Otherwise, it's covered by another window, so include it in picker
                debugLog("WindowManager: Including overlapped snap-positioned window '\(ownerName)'")
            }
            
            let cgTitle = WindowListCache.getTitle(windowInfo) ?? ownerName
            
            candidates.append(WindowCandidate(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                cgTitle: cgTitle,
                cgFrame: cgFrame,
                nsFrame: nsFrame
            ))
        }
        
        // Second pass: identify apps with multiple windows (need real titles)
        var windowCountByPID: [pid_t: Int] = [:]
        for candidate in candidates {
            windowCountByPID[candidate.ownerPID, default: 0] += 1
        }
        let multiWindowPIDs = Set(windowCountByPID.filter { $0.value > 1 }.keys)
        
        // Third pass: build final WindowInfo array
        var windows: [WindowInfo] = []
        for candidate in candidates {
            let title: String
            
            if multiWindowPIDs.contains(candidate.ownerPID) {
                // Fetch real title via Accessibility API for disambiguation
                title = getRealWindowTitle(forFrame: candidate.cgFrame, ownerPID: candidate.ownerPID) 
                    ?? candidate.cgTitle
            } else {
                title = candidate.cgTitle
            }
            
            debugLog("WindowManager: Window ID \(candidate.windowID) '\(title)' at frame \(candidate.nsFrame)")
            
            windows.append(WindowInfo(
                windowID: candidate.windowID,
                ownerPID: candidate.ownerPID,
                ownerName: candidate.ownerName,
                title: title,
                frame: candidate.nsFrame
            ))
        }
        
        debugLog("WindowManager: Found \(windows.count) other windows (\(multiWindowPIDs.count) apps with multiple windows)")
        return windows
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
        // Get the app's AX element
        let appElement = AXUIElementCreateApplication(ownerPID)
        
        // Get all windows of the app
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            debugLog("WindowManager: Failed to get windows for PID \(ownerPID)")
            return false
        }
        
        // Convert stored frame to AX coordinates for matching
        let storedAXFrame = CoordinateConverter.nsToAX(storedFrame)
        
        debugLog("WindowManager: Looking for window at stored frame \(storedFrame) (AX: \(storedAXFrame))")
        
        // Find matching AX window using the STORED frame (not fresh lookup)
        for axWindow in windows {
            guard let axPosition = getWindowPosition(axWindow),
                  let axSize = getWindowSize(axWindow) else {
                continue
            }
            
            let axFrame = CGRect(origin: axPosition, size: axSize)
            
            // Compare current AX frame with stored AX frame
            if FrameMatcher.matchesExact(axFrame, storedAXFrame) {
                // Found the window - raise it to front and activate the app
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                
                let app = NSRunningApplication(processIdentifier: ownerPID)
                app?.activate(options: [.activateIgnoringOtherApps])
                
                let startFrame = CoordinateConverter.axToNS(axFrame)
                let screen = screenManager.screen(for: startFrame)
                let targetFrame = position.frame(in: screen.visibleFrame, fullFrame: screen.frame)
                
                // Animate the window into place
                WindowAnimator.shared.animate(window: axWindow, from: startFrame, to: targetFrame)
                
                debugLog("WindowManager: Snapping window \(windowID) from \(startFrame) to \(targetFrame)")
                return true
            }
        }
        
        debugLog("WindowManager: Could not find matching AX window for stored frame \(storedFrame)")
        return false
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
    
    // MARK: - Private Helpers
    
    /// Get the frontmost window of the frontmost application
    private func getFrontmostWindow() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        guard result == .success, let window = windowRef else {
            // Try getting the first window if no focused window
            var windowsRef: CFTypeRef?
            let windowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            
            if windowsResult == .success,
               let windows = windowsRef as? [AXUIElement],
               let firstWindow = windows.first {
                return firstWindow
            }
            return nil
        }
        
        return (window as! AXUIElement)
    }
    
    /// Get the current frame of a window in NSScreen coordinates
    /// - Parameter window: The window to get the frame for
    /// - Returns: The window frame in NSScreen coordinates (bottom-left origin, Y-up)
    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = getWindowPosition(window),
              let size = getWindowSize(window) else {
            return nil
        }
        
        // AX API returns position as top-left corner in top-left origin coords
        let axFrame = CGRect(origin: position, size: size)
        
        // Convert to NSScreen coordinates using shared converter
        return CoordinateConverter.axToNS(axFrame)
    }
    
    /// Get window position
    private func getWindowPosition(_ window: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
        
        guard result == .success, let positionValue = positionRef else {
            return nil
        }
        
        var position = CGPoint.zero
        if AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) {
            return position
        }
        return nil
    }
    
    /// Get window size
    private func getWindowSize(_ window: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        
        guard result == .success, let sizeValue = sizeRef else {
            return nil
        }
        
        var size = CGSize.zero
        if AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }
    
    /// Get window title via Accessibility API
    private func getWindowTitle(_ window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        
        guard result == .success, let title = titleRef as? String, !title.isEmpty else {
            return nil
        }
        return title
    }
    
    /// Get the real window title for a window by matching its frame to an AXUIElement
    private func getRealWindowTitle(forFrame cgFrame: CGRect, ownerPID: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(ownerPID)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            return nil
        }
        
        for axWindow in windows {
            guard let axPosition = getWindowPosition(axWindow),
                  let axSize = getWindowSize(axWindow) else {
                continue
            }
            
            let axFrame = CGRect(origin: axPosition, size: axSize)
            
            // Match by frame using FrameMatcher
            if FrameMatcher.matchesExact(axFrame, cgFrame) {
                return getWindowTitle(axWindow)
            }
        }
        
        return nil
    }
}
