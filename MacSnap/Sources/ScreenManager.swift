import AppKit
import CoreGraphics

/// Manages multi-monitor detection and screen calculations
final class ScreenManager {
    
    static let shared = ScreenManager()
    
    // MARK: - Cached Screen Data
    
    private var _sortedScreens: [NSScreen]?
    
    private init() {
        // Subscribe to screen configuration changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateScreenCache()
        }
    }
    
    /// Invalidate cached screen data when configuration changes
    private func invalidateScreenCache() {
        _sortedScreens = nil
        CoordinateConverter.invalidateCache()
        debugLog("ScreenManager: Screen cache invalidated")
    }
    
    /// Get all available screens sorted by their x position (left to right)
    /// Cached for performance; invalidated on screen configuration changes
    var sortedScreens: [NSScreen] {
        if let cached = _sortedScreens {
            return cached
        }
        let sorted = NSScreen.screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
        _sortedScreens = sorted
        return sorted
    }
    
    /// Get the screen containing the given point
    /// - Parameter point: A point in global screen coordinates
    /// - Returns: The screen containing the point, or the main screen as fallback
    func screen(containing point: CGPoint) -> NSScreen {
        // Convert from CG coordinates (origin bottom-left) to NS coordinates
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }
    
    /// Get the screen containing the given window frame
    /// - Parameter windowFrame: The window's frame in screen coordinates
    /// - Returns: The screen where most of the window is visible
    func screen(for windowFrame: CGRect) -> NSScreen {
        // Find the screen with the most overlap
        var bestScreen = NSScreen.main ?? NSScreen.screens.first!
        var bestOverlap: CGFloat = 0
        
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(windowFrame)
            let overlap = intersection.width * intersection.height
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestScreen = screen
            }
        }
        
        return bestScreen
    }
    
    /// Get the adjacent screen in the specified direction
    /// - Parameters:
    ///   - currentScreen: The current screen
    ///   - direction: Direction to look for adjacent screen
    /// - Returns: The adjacent screen if one exists, nil otherwise
    func adjacentScreen(from currentScreen: NSScreen, direction: MonitorDirection) -> NSScreen? {
        let screens = sortedScreens
        guard let currentIndex = screens.firstIndex(of: currentScreen) else {
            return nil
        }
        
        switch direction {
        case .left:
            return currentIndex > 0 ? screens[currentIndex - 1] : nil
        case .right:
            return currentIndex < screens.count - 1 ? screens[currentIndex + 1] : nil
        }
    }
    
    /// Calculate equivalent position on target screen
    /// Maintains relative position and size ratios
    /// - Parameters:
    ///   - windowFrame: Original window frame
    ///   - fromScreen: Source screen
    ///   - toScreen: Target screen
    /// - Returns: New frame on the target screen
    func translateFrame(_ windowFrame: CGRect, from fromScreen: NSScreen, to toScreen: NSScreen) -> CGRect {
        let fromVisible = fromScreen.visibleFrame
        let toVisible = toScreen.visibleFrame
        
        // Calculate relative position within source screen
        let relativeX = (windowFrame.origin.x - fromVisible.origin.x) / fromVisible.width
        let relativeY = (windowFrame.origin.y - fromVisible.origin.y) / fromVisible.height
        let relativeWidth = windowFrame.width / fromVisible.width
        let relativeHeight = windowFrame.height / fromVisible.height
        
        // Apply to target screen
        return CGRect(
            x: toVisible.origin.x + (relativeX * toVisible.width),
            y: toVisible.origin.y + (relativeY * toVisible.height),
            width: relativeWidth * toVisible.width,
            height: relativeHeight * toVisible.height
        )
    }
}
