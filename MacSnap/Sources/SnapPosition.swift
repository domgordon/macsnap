import Foundation
import CoreGraphics

/// Defines all possible window snap positions
enum SnapPosition: CaseIterable {
    // Halves
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    
    // Quarters
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    
    // Full
    case maximize
    
    /// Calculate the target frame for this snap position
    /// - Parameter visibleFrame: The visible frame (used for dock position detection)
    /// - Parameter fullFrame: The full screen frame
    /// - Returns: The calculated frame for the window
    func frame(in visibleFrame: CGRect, fullFrame: CGRect? = nil) -> CGRect {
        guard let fullFrame = fullFrame else {
            // Fallback to visible frame if full frame not provided
            return frameUsingFullScreen(visibleFrame)
        }
        
        return frameUsingFullScreen(fullFrame, visibleFrame: visibleFrame)
    }
    
    /// Calculate frame using full screen dimensions, respecting menu bar and dock
    private func frameUsingFullScreen(_ fullFrame: CGRect, visibleFrame: CGRect? = nil) -> CGRect {
        let visible = visibleFrame ?? fullFrame
        
        // Calculate menu bar height (difference at the top)
        // In macOS coordinates, higher Y = higher on screen
        let menuBarHeight = fullFrame.maxY - visible.maxY
        
        // Calculate dock height (difference at the bottom)
        let dockHeight = visible.minY - fullFrame.minY
        
        // Calculate dock width adjustments (if dock is on sides)
        let dockLeftWidth = visible.minX - fullFrame.minX
        let dockRightWidth = fullFrame.maxX - visible.maxX
        
        // Our usable area: full screen minus menu bar, respecting dock
        let x = fullFrame.origin.x + dockLeftWidth
        let y = fullFrame.origin.y + dockHeight
        let width = fullFrame.width - dockLeftWidth - dockRightWidth
        let height = fullFrame.height - menuBarHeight - dockHeight
        
        let halfWidth = width / 2
        let halfHeight = height / 2
        
        // Note: macOS uses bottom-left origin (Y=0 at bottom)
        switch self {
        case .leftHalf:
            return CGRect(x: x, y: y, width: halfWidth, height: height)
        case .rightHalf:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: height)
        case .topHalf:
            return CGRect(x: x, y: y + halfHeight, width: width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: x, y: y, width: width, height: halfHeight)
        case .topLeftQuarter:
            return CGRect(x: x, y: y + halfHeight, width: halfWidth, height: halfHeight)
        case .topRightQuarter:
            return CGRect(x: x + halfWidth, y: y + halfHeight, width: halfWidth, height: halfHeight)
        case .bottomLeftQuarter:
            return CGRect(x: x, y: y, width: halfWidth, height: halfHeight)
        case .bottomRightQuarter:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: halfHeight)
        case .maximize:
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }
    
    /// Human-readable description of the position
    var displayName: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeftQuarter: return "Top Left"
        case .topRightQuarter: return "Top Right"
        case .bottomLeftQuarter: return "Bottom Left"
        case .bottomRightQuarter: return "Bottom Right"
        case .maximize: return "Maximize"
        }
    }
    
    /// The opposite half position for snap assist picker
    /// Returns the complementary half position, or nil for quarters/maximize
    var oppositeHalf: SnapPosition? {
        switch self {
        case .leftHalf: return .rightHalf
        case .rightHalf: return .leftHalf
        case .topHalf: return .bottomHalf
        case .bottomHalf: return .topHalf
        default: return nil
        }
    }
    
    /// The two quarters contained within this half position
    /// Returns nil for quarters/maximize (only halves contain quarters)
    var quarters: (SnapPosition, SnapPosition)? {
        switch self {
        case .leftHalf: return (.topLeftQuarter, .bottomLeftQuarter)
        case .rightHalf: return (.topRightQuarter, .bottomRightQuarter)
        case .topHalf: return (.topLeftQuarter, .topRightQuarter)
        case .bottomHalf: return (.bottomLeftQuarter, .bottomRightQuarter)
        default: return nil
        }
    }
    
    /// The sibling quarter in the same vertical half (top <-> bottom)
    /// Returns nil for halves/maximize (only quarters have siblings)
    var siblingQuarter: SnapPosition? {
        switch self {
        case .topLeftQuarter: return .bottomLeftQuarter
        case .bottomLeftQuarter: return .topLeftQuarter
        case .topRightQuarter: return .bottomRightQuarter
        case .bottomRightQuarter: return .topRightQuarter
        default: return nil
        }
    }
    
    /// Whether this position is a half (left, right, top, or bottom)
    var isHalf: Bool {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return true
        default: return false
        }
    }
    
    /// Whether this position is a quarter
    var isQuarter: Bool {
        switch self {
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter: return true
        default: return false
        }
    }
}

/// Direction for moving windows between monitors
enum MonitorDirection {
    case left
    case right
}
