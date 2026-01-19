import AppKit

/// Shared tolerance-based frame comparison utilities.
/// Consolidates duplicate frame matching logic from WindowManager and ScreenLayout.
enum FrameMatcher {
    
    // MARK: - Tolerances
    
    /// Tolerance for position matching (origin x/y)
    static let positionTolerance: CGFloat = 10.0
    
    /// Tolerance for size matching (width/height)
    static let sizeTolerance: CGFloat = 20.0
    
    /// Smaller tolerance for exact matching (used in window lookup)
    static let exactTolerance: CGFloat = 5.0
    
    // MARK: - Frame Matching
    
    /// Check if two frames match within default tolerances
    /// - Parameters:
    ///   - a: First frame
    ///   - b: Second frame
    /// - Returns: true if frames match within tolerance
    static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        matches(a, b, positionTolerance: positionTolerance, sizeTolerance: sizeTolerance)
    }
    
    /// Check if two frames match within specified tolerances
    /// - Parameters:
    ///   - a: First frame
    ///   - b: Second frame
    ///   - positionTolerance: Maximum allowed difference for x/y
    ///   - sizeTolerance: Maximum allowed difference for width/height
    /// - Returns: true if frames match within tolerance
    static func matches(_ a: CGRect, _ b: CGRect, positionTolerance: CGFloat, sizeTolerance: CGFloat) -> Bool {
        let matchesX = abs(a.origin.x - b.origin.x) < positionTolerance
        let matchesY = abs(a.origin.y - b.origin.y) < positionTolerance
        let matchesWidth = abs(a.width - b.width) < sizeTolerance
        let matchesHeight = abs(a.height - b.height) < sizeTolerance
        return matchesX && matchesY && matchesWidth && matchesHeight
    }
    
    /// Check if two frames match exactly (using smaller tolerance)
    /// Used for matching AX windows to CG window info
    static func matchesExact(_ a: CGRect, _ b: CGRect) -> Bool {
        matches(a, b, positionTolerance: exactTolerance, sizeTolerance: exactTolerance)
    }
    
    // MARK: - Snap Position Detection
    
    /// Detect the current snap position of a window based on its frame
    /// - Parameters:
    ///   - frame: The window's frame in NSScreen coordinates
    ///   - screen: The screen the window is on
    /// - Returns: The matching SnapPosition if the window is snapped, nil if unsnapped
    static func detectSnapPosition(for frame: CGRect, on screen: NSScreen) -> SnapPosition? {
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        
        for position in SnapPosition.allCases {
            let targetFrame = position.frame(in: visibleFrame, fullFrame: fullFrame)
            if matches(frame, targetFrame) {
                return position
            }
        }
        
        return nil
    }
}
