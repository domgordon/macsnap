import Foundation

/// Direction for snap transitions (keyboard arrow directions)
enum SnapDirection {
    case up
    case down
    case left
    case right
}

/// Result of a snap transition
enum SnapTransitionResult {
    case snap(SnapPosition)
    case unsnapToMiddle
    case minimize
}

/// Data-driven snap position transition logic.
/// Replaces verbose switch statements with a lookup table approach.
enum SnapStateMachine {
    
    // MARK: - Down Action Type
    
    /// Actions for down direction (needs three states: snap, unsnap, minimize)
    private enum DownAction {
        case snap(SnapPosition)
        case unsnap
        case minimize
    }
    
    // MARK: - Transition Tables
    
    /// Transitions for the UP direction
    /// Maps current position (nil = unsnapped) to target position
    private static let upTransitions: [SnapPosition?: SnapPosition] = [
        // Unsnapped → Maximize
        nil: .maximize,
        
        // Left side: climb up the left edge
        .leftHalf: .topLeftQuarter,
        .topLeftQuarter: .maximize,
        .bottomLeftQuarter: .leftHalf,
        
        // Right side: climb up the right edge
        .rightHalf: .topRightQuarter,
        .topRightQuarter: .maximize,
        .bottomRightQuarter: .rightHalf,
        
        // Vertical: bottom → maximize → top
        .bottomHalf: .maximize,
        .maximize: .topHalf,
        .topHalf: .topHalf  // Stay at top
    ]
    
    /// Transitions for the DOWN direction
    private static let downTransitions: [SnapPosition?: DownAction] = [
        // Unsnapped (middle) → Minimize
        nil: .minimize,
        
        // Center positions → unsnap to middle
        .maximize: .unsnap,
        .topHalf: .unsnap,
        .bottomHalf: .unsnap,
        
        // Left side: descend the left edge
        .leftHalf: .snap(.bottomLeftQuarter),
        .topLeftQuarter: .snap(.leftHalf),
        .bottomLeftQuarter: .minimize,
        
        // Right side: descend the right edge
        .rightHalf: .snap(.bottomRightQuarter),
        .topRightQuarter: .snap(.rightHalf),
        .bottomRightQuarter: .minimize
    ]
    
    /// Transitions for the LEFT direction
    /// nil value means "unsnap to middle"
    private static let leftTransitions: [SnapPosition?: SnapPosition?] = [
        // Unsnapped → Left Half
        nil: .leftHalf,
        
        // Horizontal halves → left quarters
        .topHalf: .topLeftQuarter,
        .bottomHalf: .bottomLeftQuarter,
        
        // Right quarters → horizontal halves first (then to left quarters)
        .topRightQuarter: .topHalf,
        .bottomRightQuarter: .bottomHalf,
        
        // Right half → unsnap to middle first
        .rightHalf: nil,
        
        // Already on left side or maximize → Left Half
        .leftHalf: .leftHalf,
        .topLeftQuarter: .leftHalf,
        .bottomLeftQuarter: .leftHalf,
        .maximize: .leftHalf
    ]
    
    /// Transitions for the RIGHT direction
    /// nil value means "unsnap to middle"
    private static let rightTransitions: [SnapPosition?: SnapPosition?] = [
        // Unsnapped → Right Half
        nil: .rightHalf,
        
        // Horizontal halves → right quarters
        .topHalf: .topRightQuarter,
        .bottomHalf: .bottomRightQuarter,
        
        // Left quarters → horizontal halves first (then to right quarters)
        .topLeftQuarter: .topHalf,
        .bottomLeftQuarter: .bottomHalf,
        
        // Left half → unsnap to middle first
        .leftHalf: nil,
        
        // Already on right side or maximize → Right Half
        .rightHalf: .rightHalf,
        .topRightQuarter: .rightHalf,
        .bottomRightQuarter: .rightHalf,
        .maximize: .rightHalf
    ]
    
    // MARK: - Public API
    
    /// Determine the target position when pressing a direction key
    /// - Parameters:
    ///   - current: The current snap position (nil if unsnapped)
    ///   - direction: The direction of the key press
    /// - Returns: The result - either a new snap position, unsnap to middle, or minimize
    static func nextPosition(from current: SnapPosition?, direction: SnapDirection) -> SnapTransitionResult {
        switch direction {
        case .up:
            // Up always has a target position (never unsnaps or minimizes)
            if let target = upTransitions[current] {
                return .snap(target)
            }
            return .snap(.maximize)
            
        case .down:
            if let action = downTransitions[current] {
                switch action {
                case .snap(let target):
                    return .snap(target)
                case .unsnap:
                    return .unsnapToMiddle
                case .minimize:
                    return .minimize
                }
            }
            // Fallback (shouldn't happen with complete table)
            return .minimize
            
        case .left:
            if let result = leftTransitions[current] {
                if let target = result {
                    return .snap(target)
                }
                return .unsnapToMiddle
            }
            return .snap(.leftHalf)
            
        case .right:
            if let result = rightTransitions[current] {
                if let target = result {
                    return .snap(target)
                }
                return .unsnapToMiddle
            }
            return .snap(.rightHalf)
        }
    }
}
