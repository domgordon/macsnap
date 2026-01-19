import Foundation

/// Direction for snap transitions (keyboard arrow directions)
enum SnapDirection {
    case up
    case down
    case left
    case right
}

/// Result of a snap transition - either a new position or unsnap to middle
enum SnapTransitionResult {
    case snap(SnapPosition)
    case unsnapToMiddle
}

/// Data-driven snap position transition logic.
/// Replaces verbose switch statements with a lookup table approach.
enum SnapStateMachine {
    
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
    /// nil value means "unsnap to middle"
    private static let downTransitions: [SnapPosition?: SnapPosition?] = [
        // Unsnapped → Bottom Half
        nil: .bottomHalf,
        
        // Center positions → unsnap to middle
        .maximize: nil,
        .topHalf: nil,
        .bottomHalf: nil,
        
        // Left side: descend the left edge
        .leftHalf: .bottomLeftQuarter,
        .topLeftQuarter: .leftHalf,
        .bottomLeftQuarter: .bottomHalf,
        
        // Right side: descend the right edge
        .rightHalf: .bottomRightQuarter,
        .topRightQuarter: .rightHalf,
        .bottomRightQuarter: .bottomHalf
    ]
    
    /// Transitions for the LEFT direction
    /// nil value means "unsnap to middle"
    private static let leftTransitions: [SnapPosition?: SnapPosition?] = [
        // Unsnapped → Left Half
        nil: .leftHalf,
        
        // Horizontal halves → left quarters
        .topHalf: .topLeftQuarter,
        .bottomHalf: .bottomLeftQuarter,
        
        // Right quarters → Left quarters (horizontal movement)
        .topRightQuarter: .topLeftQuarter,
        .bottomRightQuarter: .bottomLeftQuarter,
        
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
        
        // Left quarters → Right quarters (horizontal movement)
        .topLeftQuarter: .topRightQuarter,
        .bottomLeftQuarter: .bottomRightQuarter,
        
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
    /// - Returns: The result - either a new snap position or unsnap to middle
    static func nextPosition(from current: SnapPosition?, direction: SnapDirection) -> SnapTransitionResult {
        switch direction {
        case .up:
            // Up always has a target position (never unsnaps)
            if let target = upTransitions[current] {
                return .snap(target)
            }
            return .snap(.maximize)
            
        case .down:
            if let result = downTransitions[current] {
                if let target = result {
                    return .snap(target)
                }
                return .unsnapToMiddle
            }
            return .snap(.bottomHalf)
            
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
