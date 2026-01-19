import AppKit

/// Orchestrates the Snap Assist feature with Windows-style timing
/// Uses a cancellable delay timer to allow chained snaps before showing the picker
/// Supports multi-zone sequential picking for quarter snaps
final class SnapAssistController {
    
    static let shared = SnapAssistController()
    
    // MARK: - State
    
    private var assistWindow: SnapAssistWindow?
    private var delayTimer: DispatchWorkItem?
    private let windowManager = WindowManager.shared
    
    /// Queue of positions waiting to be filled (in priority order: TL, TR, BL, BR)
    private var pendingPositions: [SnapPosition] = []
    
    /// The currently active position (showing app tiles)
    private var activePosition: SnapPosition?
    
    /// The screen we're showing pickers on
    private var currentScreen: NSScreen?
    
    /// PID to exclude from window lists
    private var excludePID: pid_t?
    
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
        
        // Full screen / maximize doesn't trigger picker
        if snappedPosition == .maximize {
            debugLog("SnapAssist: Full screen snap, no picker needed")
            return
        }
        
        // Only halves and quarters trigger picker
        guard snappedPosition.oppositeHalf != nil || snappedPosition.siblingQuarter != nil else {
            debugLog("SnapAssist: Position \(snappedPosition) doesn't trigger picker")
            return
        }
        
        debugLog("SnapAssist: Scheduling assist after \(snappedPosition) in \(assistDelay)s")
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.showAssistUsingLayout(snappedPosition: snappedPosition, on: screen, excludingPID: excludePID)
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
        pendingPositions = []
        activePosition = nil
        currentScreen = nil
        excludePID = nil
        debugLog("SnapAssist: Dismissed")
    }
    
    // MARK: - ScreenLayout-Based Picker Logic
    
    private func showAssistUsingLayout(snappedPosition: SnapPosition, on screen: NSScreen, excludingPID excludePID: pid_t?) {
        // Create layout snapshot
        let layout = ScreenLayout(screen: screen, excludingPID: excludePID)
        
        // Check if full screen is already filled
        if layout.isFullScreenFilled {
            debugLog("SnapAssist: Full screen is filled, no picker needed")
            return
        }
        
        // Get positions needing fill (may be halves or quarters depending on context)
        let positionsNeedingFill = layout.positionsNeedingFill(after: snappedPosition)
        
        guard !positionsNeedingFill.isEmpty else {
            debugLog("SnapAssist: No positions need filling")
            return
        }
        
        // Get available windows to show
        let otherWindows = windowManager.getOtherWindows(excludingPID: excludePID, on: screen)
        
        guard !otherWindows.isEmpty else {
            debugLog("SnapAssist: No other windows to show")
            return
        }
        
        // Store state for multi-zone flow
        self.pendingPositions = positionsNeedingFill
        self.activePosition = positionsNeedingFill.first
        self.currentScreen = screen
        self.excludePID = excludePID
        
        debugLog("SnapAssist: Showing picker for \(positionsNeedingFill.count) positions: \(positionsNeedingFill)")
        
        // Show the picker
        showPickerWindow(windows: otherWindows, allPositions: positionsNeedingFill, on: screen)
    }
    
    private func showPickerWindow(windows: [WindowInfo], allPositions: [SnapPosition], on screen: NSScreen) {
        guard let activePosition = allPositions.first else { return }
        
        assistWindow = SnapAssistWindow(
            windows: windows,
            allPositions: allPositions,
            activePosition: activePosition,
            screen: screen
        )
        
        assistWindow?.onWindowSelected = { [weak self] windowInfo in
            self?.handleWindowSelected(windowInfo)
        }
        
        assistWindow?.onDismiss = { [weak self] in
            self?.dismiss()
        }
        
        // Show and activate the window
        assistWindow?.makeKeyAndOrderFront(nil)
        
        // Ensure window captures keyboard focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.assistWindow?.makeKey()
        }
    }
    
    // MARK: - Selection Handling
    
    private func handleWindowSelected(_ windowInfo: WindowInfo) {
        guard let activePosition = activePosition else {
            debugLog("SnapAssist: No active position for selection")
            dismiss()
            return
        }
        
        debugLog("SnapAssist: Selected window '\(windowInfo.title)' for position \(activePosition)")
        
        // Snap the window
        windowManager.snapWindow(
            windowID: windowInfo.windowID,
            ownerPID: windowInfo.ownerPID,
            to: activePosition
        )
        
        // Remove from pending queue
        pendingPositions.removeAll { $0 == activePosition }
        
        // Check if more positions need filling
        if let nextPosition = pendingPositions.first,
           let screen = currentScreen {
            // Advance to next position
            self.activePosition = nextPosition
            debugLog("SnapAssist: Advancing to next position: \(nextPosition)")
            
            // Get fresh window list (excluding the just-snapped window)
            let otherWindows = windowManager.getOtherWindows(excludingPID: excludePID, on: screen)
            
            if otherWindows.isEmpty {
                debugLog("SnapAssist: No more windows to show, dismissing")
                dismiss()
            } else {
                // Prevent resignKey from triggering dismiss during transition
                assistWindow?.onDismiss = nil
                assistWindow?.close()
                assistWindow = nil
                showPickerWindow(windows: otherWindows, allPositions: pendingPositions, on: screen)
            }
        } else {
            // All positions filled
            debugLog("SnapAssist: All positions filled, dismissing")
            dismiss()
        }
    }
}
