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
    
    /// Get the current frame of a window
    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = getWindowPosition(window),
              let size = getWindowSize(window) else {
            return nil
        }
        
        return CGRect(origin: position, size: size)
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
    /// Handles coordinate conversion from NSScreen (bottom-left origin) to AXUIElement (top-left origin)
    private func setWindowFrame(_ window: AXUIElement, to frame: CGRect) -> Bool {
        // Convert NSScreen coordinates to AXUIElement coordinates
        // NSScreen: Y=0 at bottom, origin is bottom-left of window
        // AXUIElement: Y=0 at top, position is top-left of window
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        
        // In NSScreen coords: frame.origin.y is bottom of window
        // In AX coords: we need top of window, which is origin.y + height in NSScreen
        // Then flip: axY = mainScreenHeight - (nsY + height)
        let axY = mainScreenHeight - (frame.origin.y + frame.size.height)
        let axPosition = CGPoint(x: frame.origin.x, y: axY)
        
        // Set size first, then position
        let sizeSuccess = setWindowSizeRaw(window, to: frame.size)
        let positionSuccess = setWindowPositionRaw(window, to: axPosition)
        
        // Set position again after size change to handle edge cases
        if sizeSuccess {
            _ = setWindowPositionRaw(window, to: axPosition)
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
