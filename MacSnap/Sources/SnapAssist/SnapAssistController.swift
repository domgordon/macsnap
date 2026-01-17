import AppKit

/// Orchestrates the Snap Assist feature with Windows-style timing
/// Uses a cancellable delay timer to allow chained snaps before showing the picker
final class SnapAssistController {
    
    static let shared = SnapAssistController()
    
    // MARK: - State
    
    private var assistWindow: SnapAssistWindow?
    private var delayTimer: DispatchWorkItem?
    private let windowManager = WindowManager.shared
    
    /// Whether the snap assist overlay is currently showing (modal lock state)
    var isShowingAssist: Bool {
        assistWindow != nil
    }
    
    /// Delay before showing assist (allows chained snaps)
    private let assistDelay: TimeInterval = 0.5
    
    private init() {}
    
    // MARK: - Public API
    
    /// Schedule snap assist to show after a delay (cancellable)
    /// If called again before the delay expires, the timer is reset
    /// - Parameters:
    ///   - snappedPosition: The position the window was just snapped to
    ///   - screen: The screen where the snap occurred
    ///   - excludePID: Process ID to exclude (the app that was just snapped)
    func scheduleAssist(for snappedPosition: SnapPosition, on screen: NSScreen, excludingPID excludePID: pid_t?) {
        // Cancel any pending timer
        cancelPendingAssist()
        
        // Dismiss any existing overlay (user is still adjusting)
        if isShowingAssist {
            dismiss()
        }
        
        // Only schedule for half snaps (left/right/top/bottom)
        guard let oppositePosition = snappedPosition.oppositeHalf else {
            debugLog("SnapAssist: Position \(snappedPosition) doesn't have an opposite half")
            return
        }
        
        debugLog("SnapAssist: Scheduling assist for \(oppositePosition) in \(assistDelay)s")
        
        // Create cancellable timer
        let workItem = DispatchWorkItem { [weak self] in
            self?.showAssistIfNeeded(
                oppositePosition: oppositePosition,
                on: screen,
                excludingPID: excludePID
            )
        }
        
        delayTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + assistDelay, execute: workItem)
    }
    
    /// Cancel any pending snap assist (user is still adjusting)
    func cancelPendingAssist() {
        delayTimer?.cancel()
        delayTimer = nil
        debugLog("SnapAssist: Cancelled pending assist")
    }
    
    /// Dismiss any visible snap assist window and unlock window movement
    func dismiss() {
        cancelPendingAssist()
        assistWindow?.close()
        assistWindow = nil
        debugLog("SnapAssist: Dismissed")
    }
    
    // MARK: - Private
    
    /// Determine the target position for the picker based on what's already snapped
    /// - Parameters:
    ///   - oppositeHalf: The opposite half position to check
    ///   - screen: The screen to check on
    ///   - excludePID: Process ID to exclude (the just-snapped window)
    /// - Returns: The position to show picker for, or nil to skip picker entirely
    private func determinePickerTarget(
        for oppositeHalf: SnapPosition,
        on screen: NSScreen,
        excludingPID excludePID: pid_t?
    ) -> SnapPosition? {
        // If opposite half is cleanly snapped, skip picker
        if windowManager.isPositionOccupied(oppositeHalf, on: screen, excludingPID: excludePID) {
            debugLog("SnapAssist: Opposite half \(oppositeHalf) is cleanly snapped, skipping")
            return nil
        }
        
        // Check quarters within the opposite half
        guard let (quarter1, quarter2) = oppositeHalf.quarters else {
            // No quarters (shouldn't happen for halves, but be safe)
            return oppositeHalf
        }
        
        let quarter1Occupied = windowManager.isPositionOccupied(quarter1, on: screen, excludingPID: excludePID)
        let quarter2Occupied = windowManager.isPositionOccupied(quarter2, on: screen, excludingPID: excludePID)
        
        if quarter1Occupied && quarter2Occupied {
            // Both quarters occupied, skip picker
            debugLog("SnapAssist: Both quarters \(quarter1) and \(quarter2) are occupied, skipping")
            return nil
        } else if quarter1Occupied {
            // Quarter 1 occupied, show picker for quarter 2
            debugLog("SnapAssist: \(quarter1) occupied, targeting \(quarter2)")
            return quarter2
        } else if quarter2Occupied {
            // Quarter 2 occupied, show picker for quarter 1
            debugLog("SnapAssist: \(quarter2) occupied, targeting \(quarter1)")
            return quarter1
        } else {
            // Neither quarter occupied, show picker for full opposite half
            debugLog("SnapAssist: No quarters occupied, targeting full \(oppositeHalf)")
            return oppositeHalf
        }
    }
    
    private func showAssistIfNeeded(oppositePosition: SnapPosition, on screen: NSScreen, excludingPID excludePID: pid_t?) {
        // Determine target position (may be half or quarter)
        guard let targetPosition = determinePickerTarget(
            for: oppositePosition,
            on: screen,
            excludingPID: excludePID
        ) else {
            debugLog("SnapAssist: No picker target available, skipping")
            return
        }
        
        // Get other windows (without thumbnails - just app info)
        let otherWindows = windowManager.getOtherWindows(excludingPID: excludePID, on: screen)
        
        guard !otherWindows.isEmpty else {
            debugLog("SnapAssist: No other windows to show")
            return
        }
        
        debugLog("SnapAssist: Showing picker with \(otherWindows.count) windows for position \(targetPosition)")
        
        // Calculate frame for the picker (target position area)
        let pickerFrame = targetPosition.frame(in: screen.visibleFrame, fullFrame: screen.frame)
        
        // Show the picker (enters modal lock state)
        show(windows: otherWindows, targetPosition: targetPosition, frame: pickerFrame)
    }
    
    private func show(windows: [WindowInfo], targetPosition: SnapPosition, frame: CGRect) {
        assistWindow = SnapAssistWindow(
            windows: windows,
            targetPosition: targetPosition,
            frame: frame
        )
        
        assistWindow?.onWindowSelected = { [weak self] windowInfo in
            self?.handleWindowSelected(windowInfo, position: targetPosition)
        }
        
        assistWindow?.onDismiss = { [weak self] in
            self?.assistWindow = nil
        }
        
        // Show and activate the window
        assistWindow?.makeKeyAndOrderFront(nil)
        
        // Ensure window captures keyboard focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.assistWindow?.makeKey()
        }
    }
    
    private func handleWindowSelected(_ windowInfo: WindowInfo, position: SnapPosition) {
        debugLog("SnapAssist: Selected window '\(windowInfo.title)' for position \(position)")
        
        // Clear reference and snap immediately - animation is handled in WindowManager
        assistWindow = nil
        windowManager.snapWindow(
            windowID: windowInfo.windowID,
            ownerPID: windowInfo.ownerPID,
            to: position
        )
    }
}
