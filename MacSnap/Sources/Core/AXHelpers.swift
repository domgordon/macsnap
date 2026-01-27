import AppKit
import ApplicationServices

/// Shared Accessibility API helpers for window attribute access.
/// Consolidates duplicated AX attribute fetching patterns.
enum AXHelpers {
    
    // MARK: - Generic Attribute Access
    
    /// Generic AX attribute fetcher
    /// - Parameters:
    ///   - element: The AXUIElement to query
    ///   - attribute: The attribute name (e.g., kAXPositionAttribute)
    /// - Returns: The attribute value cast to type T, or nil if not available
    static func getAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? T
    }
    
    // MARK: - Window Properties
    
    /// Get position from AXUIElement (in AX coordinates: top-left origin, Y-down)
    static func getPosition(_ element: AXUIElement) -> CGPoint? {
        guard let value: AXValue = getAttribute(element, kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }
    
    /// Get size from AXUIElement
    static func getSize(_ element: AXUIElement) -> CGSize? {
        guard let value: AXValue = getAttribute(element, kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
    
    /// Get frame combining position and size (in AX coordinates)
    static func getFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = getPosition(element),
              let size = getSize(element) else { return nil }
        return CGRect(origin: position, size: size)
    }
    
    /// Get frame in NSScreen coordinates (bottom-left origin, Y-up)
    static func getFrameInNSCoordinates(_ element: AXUIElement) -> CGRect? {
        guard let axFrame = getFrame(element) else { return nil }
        return CoordinateConverter.axToNS(axFrame)
    }
    
    /// Get title from AXUIElement
    static func getTitle(_ element: AXUIElement) -> String? {
        guard let title: String = getAttribute(element, kAXTitleAttribute), !title.isEmpty else {
            return nil
        }
        return title
    }
    
    // MARK: - Window Access
    
    /// Get the focused window attribute from an app element
    static func getFocusedWindow(_ appElement: AXUIElement) -> AXUIElement? {
        getAttribute(appElement, kAXFocusedWindowAttribute)
    }
    
    /// Get all windows from an app element
    static func getWindows(_ appElement: AXUIElement) -> [AXUIElement]? {
        getAttribute(appElement, kAXWindowsAttribute)
    }
    
    // MARK: - Window Actions
    
    /// Set window size
    /// - Returns: true if successful
    @discardableResult
    static func setSize(_ element: AXUIElement, _ size: CGSize) -> Bool {
        var mutableSize = size
        guard let sizeValue = AXValueCreate(.cgSize, &mutableSize) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) == .success
    }
    
    /// Set window position (in AX coordinates)
    /// - Returns: true if successful
    @discardableResult
    static func setPosition(_ element: AXUIElement, _ position: CGPoint) -> Bool {
        var mutablePosition = position
        guard let positionValue = AXValueCreate(.cgPoint, &mutablePosition) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue) == .success
    }
    
    /// Raise window to front
    @discardableResult
    static func raise(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
    }
}
