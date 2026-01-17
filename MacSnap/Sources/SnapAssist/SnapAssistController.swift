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
    
    private func showAssistIfNeeded(oppositePosition: SnapPosition, on screen: NSScreen, excludingPID excludePID: pid_t?) {
        // Check if opposite half is already occupied
        if windowManager.isPositionOccupied(oppositePosition, on: screen, excludingPID: excludePID) {
            debugLog("SnapAssist: Opposite position \(oppositePosition) is already occupied, skipping")
            return
        }
        
        // Get other windows (without thumbnails - just app info)
        let otherWindows = windowManager.getOtherWindows(excludingPID: excludePID, on: screen)
        
        guard !otherWindows.isEmpty else {
            debugLog("SnapAssist: No other windows to show")
            return
        }
        
        debugLog("SnapAssist: Showing picker with \(otherWindows.count) windows for position \(oppositePosition)")
        
        // Calculate frame for the picker (opposite half of screen)
        let pickerFrame = oppositePosition.frame(in: screen.visibleFrame, fullFrame: screen.frame)
        
        // Show the picker (enters modal lock state)
        show(windows: otherWindows, targetPosition: oppositePosition, frame: pickerFrame)
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
