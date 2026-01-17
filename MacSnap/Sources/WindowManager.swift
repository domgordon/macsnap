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

/// Manages window manipulation using macOS Accessibility APIs
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
        
        debugLog("WindowManager: fullFrame: \(fullFrame), visibleFrame: \(visibleFrame)")
        debugLog("WindowManager: menuBarHeight: \(fullFrame.maxY - visibleFrame.maxY), dockHeight: \(visibleFrame.minY - fullFrame.minY)")
        
        let targetFrame = position.frame(in: visibleFrame, fullFrame: fullFrame)
        debugLog("WindowManager: Target frame for \(position): \(targetFrame)")
        
        // Animate the transition for smooth feel
        animateWindowFrame(window, from: windowFrame, to: targetFrame)
        
        // Schedule snap assist for half-screen snaps or quarter snaps (cancellable delay)
        if position.oppositeHalf != nil || position.siblingQuarter != nil {
            SnapAssistController.shared.scheduleAssist(
                for: position,
                on: screen,
                excludingPID: frontPID
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
            print("MacSnap: No frontmost window found")
            return false
        }
        
        guard let windowFrame = getWindowFrame(window) else {
            print("MacSnap: Could not get window frame")
            return false
        }
        
        let currentScreen = screenManager.screen(for: windowFrame)
        
        guard let targetScreen = screenManager.adjacentScreen(from: currentScreen, direction: direction) else {
            print("MacSnap: No adjacent screen in direction \(direction)")
            return false
        }
        
        let newFrame = screenManager.translateFrame(windowFrame, from: currentScreen, to: targetScreen)
        animateWindowFrame(window, from: windowFrame, to: newFrame)
        return true
    }
    
    /// Unsnap the frontmost window to a centered "middle" state
    /// Restores the window's pre-snap size if available, otherwise uses a centered half-width fallback
    /// - Returns: true if successful
    @discardableResult
    func unsnapToMiddle() -> Bool {
        // Cancel any pending assist timer (leaving snapped state)
        SnapAssistController.shared.cancelPendingAssist()
        
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
        
        // Animate the transition for smooth feel
        animateWindowFrame(window, from: windowFrame, to: targetFrame)
        return true
    }
    
    // MARK: - Snap Assist Support
    
    /// Get the process ID of the frontmost application
    var frontmostAppPID: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
    
    /// Get all visible windows except those belonging to the specified app
    /// - Parameter excludePID: Process ID to exclude (typically the frontmost app)
    /// - Parameter screen: The screen to get windows for
    /// - Returns: Array of WindowInfo for eligible windows
    func getOtherWindows(excludingPID excludePID: pid_t?, on screen: NSScreen) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugLog("WindowManager: Failed to get window list")
            return []
        }
        
        var windows: [WindowInfo] = []
        
        for windowInfo in windowList {
            // Get required properties
            guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = windowInfo[kCGWindowLayer as String] as? Int else {
                continue
            }
            
            // Skip windows from excluded app
            if let excludePID = excludePID, ownerPID == excludePID {
                continue
            }
            
            // Skip non-normal windows (layer 0 = normal windows)
            if layer != 0 {
                continue
            }
            
            // Skip very small windows (likely tooltips, etc.)
            let width = boundsDict["Width"] ?? 0
            let height = boundsDict["Height"] ?? 0
            if width < 100 || height < 100 {
                continue
            }
            
            // Skip MacSnap itself
            if ownerName == "MacSnap" {
                continue
            }
            
            // Get window title (optional)
            let title = windowInfo[kCGWindowName as String] as? String ?? ownerName
            
            // Convert CG bounds to NSScreen coordinates
            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            let cgFrame = CGRect(x: cgX, y: cgY, width: width, height: height)
            let nsFrame = convertAXFrameToNSScreen(cgFrame)
            
            // Check if window is on the specified screen
            let windowCenter = CGPoint(x: nsFrame.midX, y: nsFrame.midY)
            if !screen.frame.contains(windowCenter) {
                continue
            }
            
            let info = WindowInfo(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                title: title,
                frame: nsFrame
            )
            windows.append(info)
        }
        
        debugLog("WindowManager: Found \(windows.count) other windows")
        return windows
    }
    
    /// Check if a screen half has a "clean snap" - a window properly snapped with nothing overlapping it
    /// Returns true only if the topmost window in the zone is cleanly snapped to the position
    /// - Parameters:
    ///   - position: The snap position to check (any half position)
    ///   - screen: The screen to check on
    ///   - excludePID: Process ID to exclude from the check (the just-snapped window)
    /// - Returns: true if there's a clean snap (skip picker), false otherwise (show picker)
    func isPositionOccupied(_ position: SnapPosition, on screen: NSScreen, excludingPID excludePID: pid_t?) -> Bool {
        let zoneFrame = position.frame(in: screen.visibleFrame, fullFrame: screen.frame)
        let positionTolerance: CGFloat = 5.0
        let sizeTolerance: CGFloat = 20.0
        
        // Windows are returned in z-order (front to back)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        // Find the first (topmost) window that overlaps the zone
        // If it's cleanly snapped -> return true (skip picker)
        // If it's not snapped (just overlapping) -> return false (show picker)
        // If no windows overlap the zone -> return false (show picker)
        
        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  let ownerName = windowInfo[kCGWindowOwnerName as String] as? String else {
                continue
            }
            
            // Skip excluded app and non-normal windows
            if let excludePID = excludePID, ownerPID == excludePID { continue }
            if layer != 0 { continue }
            if ownerName == "MacSnap" { continue }
            
            let width = boundsDict["Width"] ?? 0
            let height = boundsDict["Height"] ?? 0
            
            // Skip small windows (tooltips, etc.)
            if width < 200 || height < 200 { continue }
            
            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            let cgFrame = CGRect(x: cgX, y: cgY, width: width, height: height)
            let nsFrame = convertAXFrameToNSScreen(cgFrame)
            
            // Check if this window overlaps the zone at all
            if !nsFrame.intersects(zoneFrame) { continue }
            
            // This is the topmost window in the zone - check if it's cleanly snapped
            let matchesX = abs(nsFrame.origin.x - zoneFrame.origin.x) < positionTolerance
            let matchesY = abs(nsFrame.origin.y - zoneFrame.origin.y) < positionTolerance
            let matchesWidth = abs(nsFrame.width - zoneFrame.width) < sizeTolerance
            let matchesHeight = abs(nsFrame.height - zoneFrame.height) < sizeTolerance
            
            if matchesX && matchesY && matchesWidth && matchesHeight {
                debugLog("WindowManager: Position \(position) has clean snap by \(ownerName)")
                return true
            } else {
                debugLog("WindowManager: Position \(position) zone overlapped by non-snapped window \(ownerName)")
                return false
            }
        }
        
        // No windows overlap the zone
        debugLog("WindowManager: Position \(position) zone is empty")
        return false
    }
    
    /// Check if a zone is empty (no windows overlapping it at all)
    /// Used for sibling quarter picker - only show picker if zone is truly empty
    /// - Parameters:
    ///   - position: The snap position to check
    ///   - screen: The screen to check on
    ///   - excludePID: Process ID to exclude from the check
    /// - Returns: true if zone is empty (no overlapping windows), false otherwise
    func isZoneEmpty(_ position: SnapPosition, on screen: NSScreen, excludingPID excludePID: pid_t?) -> Bool {
        let zoneFrame = position.frame(in: screen.visibleFrame, fullFrame: screen.frame)
        
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return true
        }
        
        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  let ownerName = windowInfo[kCGWindowOwnerName as String] as? String else {
                continue
            }
            
            // Skip excluded app and non-normal windows
            if let excludePID = excludePID, ownerPID == excludePID { continue }
            if layer != 0 { continue }
            if ownerName == "MacSnap" { continue }
            
            let width = boundsDict["Width"] ?? 0
            let height = boundsDict["Height"] ?? 0
            
            // Skip small windows
            if width < 200 || height < 200 { continue }
            
            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            let cgFrame = CGRect(x: cgX, y: cgY, width: width, height: height)
            let nsFrame = convertAXFrameToNSScreen(cgFrame)
            
            // If any window overlaps the zone, it's not empty
            if nsFrame.intersects(zoneFrame) {
                debugLog("WindowManager: Zone \(position) is covered by \(ownerName)")
                return false
            }
        }
        
        debugLog("WindowManager: Zone \(position) is empty")
        return true
    }
    
    /// Snap a specific window (by window ID) to a position
    /// - Parameters:
    ///   - windowID: The CGWindowID of the window to snap
    ///   - ownerPID: The process ID that owns the window
    ///   - position: The target snap position
    /// - Returns: true if successful
    @discardableResult
    func snapWindow(windowID: CGWindowID, ownerPID: pid_t, to position: SnapPosition) -> Bool {
        // Get the app's AX element
        let appElement = AXUIElementCreateApplication(ownerPID)
        
        // Get all windows of the app
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            debugLog("WindowManager: Failed to get windows for PID \(ownerPID)")
            return false
        }
        
        // Find the matching window by comparing position/size
        // Note: AX doesn't expose CGWindowID directly, so we match by frame
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        // Find the CG window info to get its frame
        var targetCGFrame: CGRect?
        for info in windowList {
            if let wid = info[kCGWindowNumber as String] as? CGWindowID, wid == windowID,
               let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] {
                targetCGFrame = CGRect(
                    x: bounds["X"] ?? 0,
                    y: bounds["Y"] ?? 0,
                    width: bounds["Width"] ?? 0,
                    height: bounds["Height"] ?? 0
                )
                break
            }
        }
        
        guard let cgFrame = targetCGFrame else {
            debugLog("WindowManager: Could not find frame for window \(windowID)")
            return false
        }
        
        // Find matching AX window
        for axWindow in windows {
            guard let axPosition = getWindowPosition(axWindow),
                  let axSize = getWindowSize(axWindow) else {
                continue
            }
            
            // Compare frames (AX position is in same coordinate system as CG bounds)
            let tolerance: CGFloat = 5.0
            if abs(axPosition.x - cgFrame.origin.x) < tolerance &&
               abs(axPosition.y - cgFrame.origin.y) < tolerance &&
               abs(axSize.width - cgFrame.width) < tolerance &&
               abs(axSize.height - cgFrame.height) < tolerance {
                
                // Found the window - activate it and snap with animation
                let app = NSRunningApplication(processIdentifier: ownerPID)
                app?.activate(options: [.activateIgnoringOtherApps])
                
                let startFrame = self.convertAXFrameToNSScreen(CGRect(origin: axPosition, size: axSize))
                let screen = self.screenManager.screen(for: startFrame)
                let targetFrame = position.frame(in: screen.visibleFrame, fullFrame: screen.frame)
                
                // Animate the window into place
                self.animateWindowFrame(axWindow, from: startFrame, to: targetFrame)
                
                debugLog("WindowManager: Snapping window \(windowID) to \(position)")
                return true
            }
        }
        
        debugLog("WindowManager: Could not find matching AX window for \(windowID)")
        return false
    }
    
    // MARK: - Coordinate Conversion
    
    /// Height of the primary screen, used for coordinate conversion
    private var mainScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }
    
    /// Convert a frame from AX coordinates (top-left origin, Y-down) to NSScreen coordinates (bottom-left origin, Y-up)
    /// - Parameter axFrame: Frame in AX coordinate system where position is top-left corner
    /// - Returns: Frame in NSScreen coordinate system where origin is bottom-left corner
    private func convertAXFrameToNSScreen(_ axFrame: CGRect) -> CGRect {
        // AX: position.y is top of window, Y increases downward
        // NSScreen: origin.y is bottom of window, Y increases upward
        // Bottom of window in AX coords: axFrame.origin.y + axFrame.height
        // In NSScreen: origin.y = mainScreenHeight - (ax_top + height) = mainScreenHeight - ax_bottom
        let nsY = mainScreenHeight - (axFrame.origin.y + axFrame.height)
        return CGRect(x: axFrame.origin.x, y: nsY, width: axFrame.width, height: axFrame.height)
    }
    
    /// Convert a frame from NSScreen coordinates (bottom-left origin, Y-up) to AX coordinates (top-left origin, Y-down)
    /// - Parameter nsFrame: Frame in NSScreen coordinate system where origin is bottom-left corner
    /// - Returns: Frame in AX coordinate system where position is top-left corner
    private func convertNSScreenFrameToAX(_ nsFrame: CGRect) -> CGRect {
        // NSScreen: origin.y is bottom of window, Y increases upward
        // AX: position.y is top of window, Y increases downward
        // Top of window in NSScreen coords: nsFrame.origin.y + nsFrame.height
        // In AX: position.y = mainScreenHeight - (ns_bottom + height) = mainScreenHeight - ns_top
        let axY = mainScreenHeight - (nsFrame.origin.y + nsFrame.height)
        return CGRect(x: nsFrame.origin.x, y: axY, width: nsFrame.width, height: nsFrame.height)
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
        debugLog("WindowManager: Raw AX frame: \(axFrame), mainScreenHeight: \(mainScreenHeight)")
        
        // Convert to NSScreen coordinates for consistent usage throughout
        let nsFrame = convertAXFrameToNSScreen(axFrame)
        debugLog("WindowManager: Converted to NSScreen frame: \(nsFrame)")
        return nsFrame
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
    
    /// Animate window frame from current position to target
    /// Uses ease-out timing for a snappy, smooth feel
    /// - Parameters:
    ///   - window: The AXUIElement window to animate
    ///   - startFrame: Starting frame in NSScreen coordinates
    ///   - endFrame: Target frame in NSScreen coordinates
    private func animateWindowFrame(_ window: AXUIElement, from startFrame: CGRect, to endFrame: CGRect) {
        // Snappy animation: 80ms total, 6 steps for smooth interpolation
        let duration: TimeInterval = 0.08
        let steps = 6
        let stepDuration = duration / Double(steps)
        
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            // Ease-out cubic: starts fast, decelerates smoothly
            let easedProgress = 1 - pow(1 - progress, 3)
            
            let currentFrame = interpolateFrame(from: startFrame, to: endFrame, progress: easedProgress)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) { [weak self] in
                self?.setWindowFrameRaw(window, to: currentFrame)
            }
        }
    }
    
    /// Interpolate between two frames
    private func interpolateFrame(from start: CGRect, to end: CGRect, progress: Double) -> CGRect {
        CGRect(
            x: start.origin.x + (end.origin.x - start.origin.x) * progress,
            y: start.origin.y + (end.origin.y - start.origin.y) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }
    
    /// Set window frame without retries (used for animation steps)
    private func setWindowFrameRaw(_ window: AXUIElement, to frame: CGRect) {
        let axFrame = convertNSScreenFrameToAX(frame)
        setWindowSizeRaw(window, to: frame.size)
        setWindowPositionRaw(window, to: axFrame.origin)
    }
    
    /// Set the frame of a window (position and size)
    /// - Parameters:
    ///   - window: The window to resize/reposition
    ///   - frame: Target frame in NSScreen coordinates (bottom-left origin, Y-up)
    /// - Returns: true if successful
    private func setWindowFrame(_ window: AXUIElement, to frame: CGRect) -> Bool {
        debugLog("WindowManager: setWindowFrame called with NSScreen frame: \(frame)")
        
        // Convert from NSScreen coordinates to AX coordinates
        let axFrame = convertNSScreenFrameToAX(frame)
        let axPosition = axFrame.origin
        debugLog("WindowManager: Converted to AX position: \(axPosition), size: \(frame.size)")
        
        // Set size first to establish dimensions
        var sizeSuccess = setWindowSizeRaw(window, to: frame.size)
        debugLog("WindowManager: Size set success: \(sizeSuccess)")
        
        // Set position after size
        let positionSuccess = setWindowPositionRaw(window, to: axPosition)
        debugLog("WindowManager: Position set success: \(positionSuccess)")
        
        // Some apps don't properly apply size/position on first attempt
        // Re-apply both to ensure the frame is fully set
        sizeSuccess = setWindowSizeRaw(window, to: frame.size)
        _ = setWindowPositionRaw(window, to: axPosition)
        
        // Verify the result
        if let finalPosition = getWindowPosition(window), let finalSize = getWindowSize(window) {
            debugLog("WindowManager: Final AX position: \(finalPosition), size: \(finalSize)")
            
            // Check if size was applied correctly (within 2px tolerance)
            let sizeDiff = abs(finalSize.height - frame.size.height)
            if sizeDiff > 2 {
                debugLog("WindowManager: WARNING - Size mismatch! Expected height \(frame.size.height), got \(finalSize.height)")
                // Try one more time
                _ = setWindowSizeRaw(window, to: frame.size)
                _ = setWindowPositionRaw(window, to: axPosition)
            }
        }
        
        return positionSuccess && sizeSuccess
    }
    
    /// Set window position in AXUIElement coordinates (raw, no conversion)
    private func setWindowPositionRaw(_ window: AXUIElement, to point: CGPoint) -> Bool {
        var position = point
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            return false
        }
        
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        return result == .success
    }
    
    /// Set window size (raw)
    private func setWindowSizeRaw(_ window: AXUIElement, to size: CGSize) -> Bool {
        var newSize = size
        guard let sizeValue = AXValueCreate(.cgSize, &newSize) else {
            return false
        }
        
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return result == .success
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
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        
        let positionTolerance: CGFloat = 10.0
        let sizeTolerance: CGFloat = 20.0
        
        // Check each snap position for a match
        for position in SnapPosition.allCases {
            let targetFrame = position.frame(in: visibleFrame, fullFrame: fullFrame)
            
            let matchesX = abs(windowFrame.origin.x - targetFrame.origin.x) < positionTolerance
            let matchesY = abs(windowFrame.origin.y - targetFrame.origin.y) < positionTolerance
            let matchesWidth = abs(windowFrame.width - targetFrame.width) < sizeTolerance
            let matchesHeight = abs(windowFrame.height - targetFrame.height) < sizeTolerance
            
            if matchesX && matchesY && matchesWidth && matchesHeight {
                debugLog("WindowManager: Detected current snap position: \(position)")
                return position
            }
        }
        
        debugLog("WindowManager: Window is unsnapped (no matching position)")
        return nil
    }
    
    /// Determine the target position when pressing "up" based on current snap state
    /// - Parameter current: The current snap position (nil if unsnapped)
    /// - Returns: The target snap position to transition to
    func targetPositionForUp(from current: SnapPosition?) -> SnapPosition {
        guard let current = current else {
            // Unsnapped → Fullscreen
            return .maximize
        }
        
        switch current {
        // Left side transitions
        case .leftHalf:
            return .topLeftQuarter
        case .topLeftQuarter:
            return .maximize
        case .bottomLeftQuarter:
            return .leftHalf
            
        // Right side transitions
        case .rightHalf:
            return .topRightQuarter
        case .topRightQuarter:
            return .maximize
        case .bottomRightQuarter:
            return .rightHalf
            
        // Fullscreen → Top Half
        case .maximize:
            return .topHalf
            
        // Already at top half → stay at top half
        case .topHalf:
            return .topHalf
            
        // Bottom half → fullscreen
        case .bottomHalf:
            return .maximize
        }
    }
    
    /// Determine the target position when pressing "left" based on current snap state
    /// - Parameter current: The current snap position (nil if unsnapped)
    /// - Returns: The target snap position, or nil to indicate "unsnap to middle"
    func targetPositionForLeft(from current: SnapPosition?) -> SnapPosition? {
        guard let current = current else {
            // Unsnapped → Left Half
            return .leftHalf
        }
        
        switch current {
        // Horizontal halves → quarters
        case .topHalf:
            return .topLeftQuarter
        case .bottomHalf:
            return .bottomLeftQuarter
            
        // Right quarters → Left quarters (horizontal movement)
        case .topRightQuarter:
            return .topLeftQuarter
        case .bottomRightQuarter:
            return .bottomLeftQuarter
            
        // Right half → middle state first
        case .rightHalf:
            return nil
            
        // Already on left side or other positions → Left Half
        case .leftHalf, .topLeftQuarter, .bottomLeftQuarter, .maximize:
            return .leftHalf
        }
    }
    
    /// Determine the target position when pressing "right" based on current snap state
    /// - Parameter current: The current snap position (nil if unsnapped)
    /// - Returns: The target snap position, or nil to indicate "unsnap to middle"
    func targetPositionForRight(from current: SnapPosition?) -> SnapPosition? {
        guard let current = current else {
            // Unsnapped → Right Half
            return .rightHalf
        }
        
        switch current {
        // Horizontal halves → quarters
        case .topHalf:
            return .topRightQuarter
        case .bottomHalf:
            return .bottomRightQuarter
            
        // Left quarters → Right quarters (horizontal movement)
        case .topLeftQuarter:
            return .topRightQuarter
        case .bottomLeftQuarter:
            return .bottomRightQuarter
            
        // Left half → middle state first
        case .leftHalf:
            return nil
            
        // Already on right side or other positions → Right Half
        case .rightHalf, .topRightQuarter, .bottomRightQuarter, .maximize:
            return .rightHalf
        }
    }
    
    /// Determine the target position when pressing "down" based on current snap state
    /// - Parameter current: The current snap position (nil if unsnapped)
    /// - Returns: The target snap position, or nil to indicate "unsnap to middle"
    func targetPositionForDown(from current: SnapPosition?) -> SnapPosition? {
        guard let current = current else {
            // Unsnapped → Bottom Half
            return .bottomHalf
        }
        
        switch current {
        // These positions go to middle state
        case .maximize, .topHalf, .bottomHalf:
            return nil
            
        // Left side transitions down
        case .leftHalf:
            return .bottomLeftQuarter
        case .topLeftQuarter:
            return .leftHalf
        case .bottomLeftQuarter:
            return .bottomHalf
            
        // Right side transitions down
        case .rightHalf:
            return .bottomRightQuarter
        case .topRightQuarter:
            return .rightHalf
        case .bottomRightQuarter:
            return .bottomHalf
        }
    }
}
