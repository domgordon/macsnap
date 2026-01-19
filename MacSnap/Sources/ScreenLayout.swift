import AppKit
import ApplicationServices

/// Represents the current layout state of a screen, tracking which areas are "filled" (clean snapped)
/// 
/// An area is considered "filled" when:
/// - **Condition 1 (Exact Fit)**: A window's position + size matches the zone exactly
/// - **Condition 2 (Not Overlapped)**: No windows at higher z-order overlap that window
struct ScreenLayout {
    
    let screen: NSScreen
    private let excludePID: pid_t?
    private let windowList: [[String: Any]]
    
    // MARK: - Initialization
    
    init(screen: NSScreen, excludingPID: pid_t?) {
        self.screen = screen
        self.excludePID = excludingPID
        
        // Use cached window list (in z-order, front to back)
        self.windowList = WindowListCache.shared.getWindowList()
    }
    
    // MARK: - Public API
    
    /// Check if a specific position (quarter, half, or full) is filled
    /// Uses two-condition check: exact fit AND not overlapped
    func isPositionFilled(_ position: SnapPosition) -> Bool {
        let zoneFrame = position.frame(in: screen.visibleFrame, fullFrame: screen.frame)
        return isZoneFilled(zoneFrame)
    }
    
    /// Check if a half is filled (either by 1 half-sized window OR 2 quarter-sized windows)
    func isHalfFilled(_ half: SnapPosition) -> Bool {
        // First check if the half itself is directly filled
        if isPositionFilled(half) {
            return true
        }
        
        // Check if both quarters within this half are filled
        guard let (quarter1, quarter2) = half.quarters else {
            return false
        }
        
        return isPositionFilled(quarter1) && isPositionFilled(quarter2)
    }
    
    /// Check if a half is completely empty (no half-sized window AND no quarter-sized windows)
    func isHalfCompletelyEmpty(_ half: SnapPosition) -> Bool {
        // If the half itself is filled, not empty
        if isPositionFilled(half) {
            return false
        }
        
        // Check if either quarter within this half is filled
        guard let (quarter1, quarter2) = half.quarters else {
            return true
        }
        
        return !isPositionFilled(quarter1) && !isPositionFilled(quarter2)
    }
    
    /// Get positions that need filling after a snap
    /// Returns halves when appropriate (empty opposite half), otherwise quarters
    /// - Parameter snappedPosition: The position just snapped to (treated as filled by definition)
    /// - Returns: Array of positions to fill (may include halves or quarters)
    func positionsNeedingFill(after snappedPosition: SnapPosition) -> [SnapPosition] {
        // Handle half snaps: check if opposite half should be filled as a whole
        if snappedPosition.isHalf, let oppositeHalf = snappedPosition.oppositeHalf {
            // If opposite half is completely empty, return it as a single position
            if isHalfCompletelyEmpty(oppositeHalf) {
                debugLog("ScreenLayout: After \(snappedPosition.displayName), opposite half is empty: [\(oppositeHalf.displayName)]")
                return [oppositeHalf]
            }
            
            // Otherwise, return unfilled quarters in the opposite half only
            guard let (q1, q2) = oppositeHalf.quarters else {
                return []
            }
            
            var result: [SnapPosition] = []
            // Maintain priority order (TL, TR, BL, BR)
            let priorityOrder: [SnapPosition] = [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
            for quarter in priorityOrder {
                if (quarter == q1 || quarter == q2) && !isPositionFilled(quarter) {
                    result.append(quarter)
                }
            }
            
            debugLog("ScreenLayout: After \(snappedPosition.displayName), quarters needing fill: \(result.map { $0.displayName })")
            return result
        }
        
        // Handle quarter snaps: return remaining quarters in priority order
        let priorityOrder: [SnapPosition] = [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
        var excludedQuarters: Set<SnapPosition> = []
        
        // The just-snapped quarter is filled by definition
        if snappedPosition.isQuarter {
            excludedQuarters.insert(snappedPosition)
        }
        
        // Check each half - if filled (by other windows), exclude both its quarters
        let halves: [SnapPosition] = [.leftHalf, .rightHalf, .topHalf, .bottomHalf]
        for half in halves {
            if isHalfFilled(half), let (q1, q2) = half.quarters {
                excludedQuarters.insert(q1)
                excludedQuarters.insert(q2)
            }
        }
        
        // Check individual quarters - if filled, exclude
        for quarter in priorityOrder {
            if excludedQuarters.contains(quarter) { continue }
            if isPositionFilled(quarter) {
                excludedQuarters.insert(quarter)
            }
        }
        
        // Return unfilled quarters in priority order
        let result = priorityOrder.filter { !excludedQuarters.contains($0) }
        debugLog("ScreenLayout: After \(snappedPosition.displayName), positions needing fill: \(result.map { $0.displayName })")
        return result
    }
    
    /// Check if full screen is filled
    var isFullScreenFilled: Bool {
        // Direct full screen fill
        if isPositionFilled(.maximize) {
            return true
        }
        
        // Both halves filled (vertical split)
        if isHalfFilled(.leftHalf) && isHalfFilled(.rightHalf) {
            return true
        }
        
        // Both halves filled (horizontal split)
        if isHalfFilled(.topHalf) && isHalfFilled(.bottomHalf) {
            return true
        }
        
        return false
    }
    
    // MARK: - Private Helpers
    
    /// Core two-condition check for a zone
    /// Condition 1: Find a window that exactly fits the zone
    /// Condition 2: No windows at higher z-order overlap it
    private func isZoneFilled(_ zoneFrame: CGRect) -> Bool {
        var foundExactFit = false
        var exactFitIndex: Int = -1
        
        // First pass: find a window that exactly fits this zone
        for (index, windowInfo) in windowList.enumerated() {
            guard let frame = WindowListCache.getFrame(windowInfo) else { continue }
            guard WindowListCache.isValidWindow(windowInfo, excludePID: excludePID, minSize: 200) else { continue }
            
            // Use FrameMatcher for consistent tolerance-based comparison
            // Note: Using exact tolerance (5.0) for zone position, but larger tolerance for size
            if FrameMatcher.matches(frame, zoneFrame, positionTolerance: 5.0, sizeTolerance: FrameMatcher.sizeTolerance) {
                foundExactFit = true
                exactFitIndex = index
                break
            }
        }
        
        guard foundExactFit else {
            return false  // Condition 1 failed
        }
        
        // Second pass: check if any window at higher z-order (lower index) overlaps it
        for index in 0..<exactFitIndex {
            let windowInfo = windowList[index]
            guard let frame = WindowListCache.getFrame(windowInfo) else { continue }
            guard WindowListCache.isValidWindow(windowInfo, excludePID: excludePID, minSize: 200) else { continue }
            
            if frame.intersects(zoneFrame) {
                debugLog("ScreenLayout: Zone overlapped by higher window at index \(index)")
                return false  // Condition 2 failed
            }
        }
        
        debugLog("ScreenLayout: Zone is filled (exact fit at index \(exactFitIndex), no overlap)")
        return true
    }
}
