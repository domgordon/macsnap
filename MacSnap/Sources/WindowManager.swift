import AppKit
import ApplicationServices

/// Manages window manipulation using macOS Accessibility APIs
final class WindowManager {
    
    static let shared = WindowManager()
    
    private let screenManager = ScreenManager.shared
    
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
        
        debugLog("WindowManager: fullFrame: \(fullFrame), visibleFrame: \(visibleFrame)")
        debugLog("WindowManager: menuBarHeight: \(fullFrame.maxY - visibleFrame.maxY), dockHeight: \(visibleFrame.minY - fullFrame.minY)")
        
        let targetFrame = position.frame(in: visibleFrame, fullFrame: fullFrame)
        debugLog("WindowManager: Target frame for \(position): \(targetFrame)")
        
        return setWindowFrame(window, to: targetFrame)
    }
    
    /// Move the frontmost window to an adjacent monitor
    /// - Parameter direction: Direction to move (left or right)
    /// - Returns: true if successful
    @discardableResult
    func moveFrontmostWindow(to direction: MonitorDirection) -> Bool {
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
        return setWindowFrame(window, to: newFrame)
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
}
