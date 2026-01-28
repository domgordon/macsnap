import AppKit

/// Single source of truth for coordinate system conversions between
/// Accessibility API (AX) coordinates and NSScreen coordinates.
///
/// AX coordinates: Origin at top-left of primary screen, Y increases downward
/// NSScreen coordinates: Origin at bottom-left of primary screen, Y increases upward
enum CoordinateConverter {
    
    // MARK: - Cached Main Screen Height
    
    private static var cachedMainScreenHeight: CGFloat?
    
    /// Height of the primary screen, cached for performance.
    /// Used as the reference point for coordinate conversion.
    static var mainScreenHeight: CGFloat {
        if let cached = cachedMainScreenHeight {
            return cached
        }
        let height = NSScreen.screens.first?.frame.height ?? 0
        cachedMainScreenHeight = height
        return height
    }
    
    /// Invalidate the cached screen height.
    /// Call this when screen configuration changes.
    static func invalidateCache() {
        cachedMainScreenHeight = nil
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert a frame from AX coordinates (top-left origin, Y-down) to NSScreen coordinates (bottom-left origin, Y-up)
    /// - Parameter axFrame: Frame in AX coordinate system where position is top-left corner
    /// - Returns: Frame in NSScreen coordinate system where origin is bottom-left corner
    static func axToNS(_ axFrame: CGRect) -> CGRect {
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
    static func nsToAX(_ nsFrame: CGRect) -> CGRect {
        // NSScreen: origin.y is bottom of window, Y increases upward
        // AX: position.y is top of window, Y increases downward
        // Top of window in NSScreen coords: nsFrame.origin.y + nsFrame.height
        // In AX: position.y = mainScreenHeight - (ns_bottom + height) = mainScreenHeight - ns_top
        let axY = mainScreenHeight - (nsFrame.origin.y + nsFrame.height)
        return CGRect(x: nsFrame.origin.x, y: axY, width: nsFrame.width, height: nsFrame.height)
    }
    
    /// Convert CG window bounds (from CGWindowListCopyWindowInfo) to NSScreen coordinates
    /// CG bounds use the same coordinate system as AX (top-left origin, Y-down)
    /// - Parameter cgBounds: Bounds dictionary from CGWindowListCopyWindowInfo
    /// - Returns: Frame in NSScreen coordinates, or nil if bounds are invalid
    static func cgBoundsToNS(_ boundsDict: [String: CGFloat]) -> CGRect? {
        guard let cgFrame = cgRect(from: boundsDict) else {
            return nil
        }
        return axToNS(cgFrame)  // CG uses same coord system as AX
    }
    
    /// Create a CGRect from a bounds dictionary (from CGWindowListCopyWindowInfo)
    /// Returns the raw frame in CG coordinates (top-left origin, Y-down)
    /// - Parameter boundsDict: Bounds dictionary with X, Y, Width, Height keys
    /// - Returns: Frame in CG coordinates, or nil if bounds are invalid
    static func cgRect(from boundsDict: [String: CGFloat]) -> CGRect? {
        guard let x = boundsDict["X"],
              let y = boundsDict["Y"],
              let width = boundsDict["Width"],
              let height = boundsDict["Height"] else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
