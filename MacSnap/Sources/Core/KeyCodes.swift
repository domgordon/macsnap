import Foundation

/// Centralized key code constants for keyboard handling.
/// Single source of truth for all key codes used across the app.
enum KeyCodes {
    // Special keys
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76  // Numpad enter
    static let tab: UInt16 = 48
    
    // Arrow keys
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

/// Direction for snap transitions (keyboard arrow directions)
enum SnapDirection: Equatable {
    case up
    case down
    case left
    case right
    
    /// Initialize from a key code, returns nil if not an arrow key
    init?(keyCode: UInt16) {
        switch keyCode {
        case KeyCodes.leftArrow: self = .left
        case KeyCodes.rightArrow: self = .right
        case KeyCodes.upArrow: self = .up
        case KeyCodes.downArrow: self = .down
        default: return nil
        }
    }
    
    /// The key code for this direction
    var keyCode: UInt16 {
        switch self {
        case .left: return KeyCodes.leftArrow
        case .right: return KeyCodes.rightArrow
        case .up: return KeyCodes.upArrow
        case .down: return KeyCodes.downArrow
        }
    }
}
