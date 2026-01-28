import AppKit

// MARK: - Snap Assist Notification

extension Notification.Name {
    /// Posted when the snap assist picker is dismissed
    /// userInfo contains: "windowSelected" (Bool) - true if a window was selected
    static let snapAssistDismissed = Notification.Name("MacSnapAssistDismissed")
}

/// Orchestrates the Snap Assist feature with Windows-style timing
/// Uses a cancellable delay timer to allow chained snaps before showing the picker
/// Supports multi-zone sequential picking for quarter snaps
final class SnapAssistController {
    
    static let shared = SnapAssistController()
    
    // MARK: - State
    
    private var assistWindow: SnapAssistWindow?
    private var delayTimer: DispatchWorkItem?
    private var scheduledAssistID: UUID?  // Used to detect if timer was cancelled
    private let windowManager = WindowManager.shared
    
    /// Queue of positions waiting to be filled (in priority order: TL, TR, BL, BR)
    private var pendingPositions: [SnapPosition] = []
    
    /// The currently active position (showing app tiles)
    private var activePosition: SnapPosition?
    
    /// The screen we're showing pickers on
    private var currentScreen: NSScreen?
    
    /// Window ID to exclude from window lists (the window that was just snapped)
    private var excludeWindowID: CGWindowID?
    
    /// The app that was frontmost before showing the picker (for focus restoration on dismiss)
    private var previousApp: NSRunningApplication?
    
    /// The position the original window was snapped to (for state machine when picker is showing)
    private(set) var originalSnappedPosition: SnapPosition?
    
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
    ///   - excludeWindowID: Window ID to exclude (the window that was just snapped)
    func scheduleAssist(for snappedPosition: SnapPosition, on screen: NSScreen, excludingWindowID excludeWindowID: CGWindowID?) {
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
        
        // Store the snapped position so we can use it for state machine when picker is showing
        self.originalSnappedPosition = snappedPosition
        
        debugLog("SnapAssist: Scheduling assist after \(snappedPosition) in \(assistDelay)s")
        
        // Generate unique ID for this schedule - allows detecting cancellation
        let scheduleID = UUID()
        self.scheduledAssistID = scheduleID
        
        let workItem = DispatchWorkItem { [weak self] in
            // Check if this schedule is still valid (wasn't cancelled or superseded)
            guard self?.scheduledAssistID == scheduleID else {
                debugLog("SnapAssist: Timer was cancelled, not showing assist")
                return
            }
            self?.showAssistUsingLayout(snappedPosition: snappedPosition, on: screen, excludingWindowID: excludeWindowID)
        }
        
        delayTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + assistDelay, execute: workItem)
    }
    
    /// Cancel any pending snap assist (user is still adjusting)
    func cancelPendingAssist() {
        scheduledAssistID = nil  // Invalidate any pending timer callback
        delayTimer?.cancel()
        delayTimer = nil
        debugLog("SnapAssist: Cancelled pending assist")
    }
    
    /// Dismiss any visible snap assist window and unlock window movement
    /// - Parameter windowSelected: Whether a window was selected from the picker (vs dismissed/cancelled)
    func dismiss(windowSelected: Bool = false) {
        cancelPendingAssist()
        
        // Clear callbacks before closing to prevent re-entry
        assistWindow?.onDismiss = nil
        assistWindow?.onWindowSelected = nil
        
        // Prevent resignKey from triggering dismissPicker animation
        assistWindow?.ignoreResignEvents = true
        
        assistWindow?.close()
        assistWindow = nil
        
        // Restore focus to the previously active app (if we still have a reference)
        // previousApp is cleared when a window is selected, so this only triggers on Escape/click-outside
        if let app = previousApp {
            debugLog("SnapAssist: Restoring focus to \(app.localizedName ?? "unknown app")")
            app.activate(options: [.activateIgnoringOtherApps])
        }
        
        pendingPositions = []
        activePosition = nil
        currentScreen = nil
        excludeWindowID = nil
        previousApp = nil
        originalSnappedPosition = nil
        
        // Clear the app icon cache to free memory
        AppIconCache.shared.clear()
        
        debugLog("SnapAssist: Dismissed (window closed, state cleared, windowSelected=\(windowSelected))")
        
        // Post notification for observers (e.g., onboarding tutorial)
        NotificationCenter.default.post(
            name: .snapAssistDismissed,
            object: nil,
            userInfo: ["windowSelected": windowSelected]
        )
    }
    
    // MARK: - ScreenLayout-Based Picker Logic
    
    private func showAssistUsingLayout(snappedPosition: SnapPosition, on screen: NSScreen, excludingWindowID excludeWindowID: CGWindowID?) {
        // Create layout snapshot (ScreenLayout checks zone fills, not which windows to show)
        let layout = ScreenLayout(screen: screen, excludingPID: nil)
        
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
        
        // Get available windows to show (excludes specific window + clean-snapped windows)
        let otherWindows = windowManager.getOtherWindows(excludingWindowID: excludeWindowID, on: screen)
        
        guard !otherWindows.isEmpty else {
            debugLog("SnapAssist: No other windows to show")
            return
        }
        
        // Store state for multi-zone flow
        self.pendingPositions = positionsNeedingFill
        self.activePosition = positionsNeedingFill.first
        self.currentScreen = screen
        self.excludeWindowID = excludeWindowID
        
        // Capture frontmost app before picker steals focus (for restoration on dismiss)
        self.previousApp = NSWorkspace.shared.frontmostApplication
        
        debugLog("SnapAssist: Showing picker for \(positionsNeedingFill.count) positions: \(positionsNeedingFill)")
        
        // Show the picker
        showPickerWindow(windows: otherWindows, allPositions: positionsNeedingFill, on: screen)
    }
    
    /// Show the picker window
    /// - Parameters:
    ///   - windows: Windows to display in the picker
    ///   - allPositions: All positions that need filling
    ///   - screen: The screen to show the picker on
    ///   - isTransition: If true, temporarily ignores resign events (for multi-zone transitions)
    private func showPickerWindow(windows: [WindowInfo], allPositions: [SnapPosition], on screen: NSScreen, isTransition: Bool = false) {
        guard let activePosition = allPositions.first else { return }
        
        // Re-activate MacSnap if transitioning (snap may have activated another app)
        if isTransition {
            NSApp.activate(ignoringOtherApps: true)
        }
        
        assistWindow = SnapAssistWindow(
            windows: windows,
            allPositions: allPositions,
            activePosition: activePosition,
            screen: screen
        )
        
        // Temporarily ignore resign events during transition setup
        if isTransition {
            assistWindow?.ignoreResignEvents = true
        }
        
        assistWindow?.onWindowSelected = { [weak self] windowInfo in
            self?.handleWindowSelected(windowInfo)
        }
        
        assistWindow?.onDismiss = { [weak self] in
            self?.dismiss()
        }
        
        // Show and activate the window
        assistWindow?.makeKeyAndOrderFront(nil)
        
        // Ensure window captures keyboard focus after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationConfig.focusDelay) { [weak self] in
            if isTransition {
                self?.assistWindow?.ignoreResignEvents = false
                debugLog("SnapAssist: Transition picker ready (resign events re-enabled)")
            }
            self?.assistWindow?.makeKey()
        }
    }
    
    // MARK: - Selection Handling
    
    private func handleWindowSelected(_ windowInfo: WindowInfo) {
        guard let activePosition = activePosition else {
            debugLog("SnapAssist: No active position for selection")
            previousApp = nil
            dismiss()
            return
        }
        
        debugLog("SnapAssist: Selected window '\(windowInfo.title)' for position \(activePosition)")
        debugLog("SnapAssist: Window stored frame: \(windowInfo.frame)")
        debugLog("SnapAssist: pendingPositions before removal: \(pendingPositions.map { $0.displayName })")
        
        // Snap the window using its STORED frame for matching (not fresh lookup)
        windowManager.snapWindow(
            windowID: windowInfo.windowID,
            ownerPID: windowInfo.ownerPID,
            storedFrame: windowInfo.frame,
            to: activePosition
        )
        
        // Remove from pending queue
        pendingPositions.removeAll { $0 == activePosition }
        debugLog("SnapAssist: pendingPositions after removal: \(pendingPositions.map { $0.displayName })")
        
        // Check if more positions need filling
        if let nextPosition = pendingPositions.first,
           let screen = currentScreen {
            // More positions to fill - set previousApp to the just-selected window's app
            // so if user escapes from the next picker, focus returns to this window
            previousApp = NSRunningApplication(processIdentifier: windowInfo.ownerPID)
            
            // Advance to next position
            self.activePosition = nextPosition
            debugLog("SnapAssist: Advancing to next position: \(nextPosition.displayName)")
            
            // Get fresh window list (excluding the original snapped window + clean-snapped windows)
            let otherWindows = windowManager.getOtherWindows(excludingWindowID: excludeWindowID, on: screen)
            debugLog("SnapAssist: Found \(otherWindows.count) windows for next picker")
            
            if otherWindows.isEmpty {
                debugLog("SnapAssist: No more windows to show, dismissing")
                dismiss(windowSelected: true)
            } else {
                debugLog("SnapAssist: Transitioning to next picker...")
                // Prevent resignKey from triggering dismiss during transition
                assistWindow?.onDismiss = nil
                assistWindow?.onWindowSelected = nil
                assistWindow?.ignoreResignEvents = true
                assistWindow?.close()
                assistWindow = nil
                
                // Defer new picker creation to next run loop to let old window fully close
                // and to re-activate MacSnap after the snap activated another app
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    debugLog("SnapAssist: Creating new picker window...")
                    self.showPickerWindow(windows: otherWindows, allPositions: self.pendingPositions, on: screen, isTransition: true)
                    debugLog("SnapAssist: New picker window created")
                }
            }
        } else {
            // All positions filled - clear previousApp so we don't override the final selected window
            previousApp = nil
            debugLog("SnapAssist: All positions filled (pendingPositions empty), dismissing")
            dismiss(windowSelected: true)
        }
    }
}
