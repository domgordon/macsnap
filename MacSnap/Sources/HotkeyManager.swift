import AppKit
import Carbon

// MARK: - Snap Action Notification

extension Notification.Name {
    /// Posted when a snap action is performed via hotkey
    /// userInfo contains: "action" (SnapActionInfo)
    static let snapActionPerformed = Notification.Name("MacSnapActionPerformed")
}

/// Information about a snap action for notification observers
struct SnapActionInfo {
    let direction: SnapDirection?
    let position: SnapPosition?
    let isUnsnapToMiddle: Bool
    let isMinimize: Bool
}

/// Manages global keyboard shortcut detection and handling
final class HotkeyManager {
    
    static let shared = HotkeyManager()
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let windowManager = WindowManager.shared
    
    /// Whether hotkey monitoring is currently active
    private(set) var isEnabled = false
    
    private init() {
        debugLog("HotkeyManager: Initialized")
    }
    
    /// Log to file for debugging
    private func log(_ message: String) {
        debugLog("HotkeyManager: \(message)")
    }
    
    // MARK: - Public API
    
    /// Start listening for global hotkeys
    func start() {
        guard !isEnabled else { return }
        
        log("Setting up hotkey monitors...")
        
        // Global monitor for when other apps are focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.log("[GLOBAL] Key event received - keyCode: \(event.keyCode), modifiers: \(event.modifierFlags.rawValue)")
            self?.handleKeyEvent(event)
        }
        
        if globalMonitor != nil {
            log("Global monitor registered successfully")
        } else {
            log("ERROR - Failed to register global monitor!")
        }
        
        // Local monitor for when this app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.log("[LOCAL] Key event received - keyCode: \(event.keyCode)")
            if self?.handleKeyEvent(event) == true {
                return nil // Consume the event
            }
            return event
        }
        
        isEnabled = true
        log("Hotkey monitoring started - Control+Option+Arrow to snap windows")
    }
    
    /// Stop listening for global hotkeys
    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        
        isEnabled = false
        log("Hotkey monitoring stopped")
    }
    
    /// Toggle hotkey monitoring on/off
    func toggle() {
        if isEnabled {
            stop()
        } else {
            start()
        }
    }
    
    // MARK: - Event Handling
    
    /// Handle a key event and perform the appropriate action
    /// - Returns: true if the event was handled
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        let hasControl = flags.contains(.control)
        let hasOption = flags.contains(.option)
        let hasCommand = flags.contains(.command)
        let hasShift = flags.contains(.shift)
        
        log("Modifiers - Ctrl:\(hasControl) Opt:\(hasOption) Cmd:\(hasCommand) Shift:\(hasShift) KeyCode:\(event.keyCode)")
        
        // Check for Control + Option (our base modifier combo)
        guard hasControl && hasOption else {
            return false
        }
        
        log("Control+Option detected! Checking for action...")
        
        // Determine the action based on modifier combination and key
        if let action = determineAction(for: event, flags: flags) {
            log("Action found: \(action)")
            performAction(action)
            return true
        }
        
        log("No matching action for keyCode \(event.keyCode)")
        return false
    }
    
    /// Determine the snap action for a given key event
    private func determineAction(for event: NSEvent, flags: NSEvent.ModifierFlags) -> SnapAction? {
        let keyCode = event.keyCode
        
        let hasCommand = flags.contains(.command)
        let hasShift = flags.contains(.shift)
        
        // Control + Option + Shift (no Cmd) + Arrow = Move between monitors
        if hasShift && !hasCommand {
            switch keyCode {
            case KeyCode.leftArrow:
                return .moveToMonitor(.left)
            case KeyCode.rightArrow:
                return .moveToMonitor(.right)
            default:
                return nil
            }
        }
        
        // Control + Option + Command + Shift + Arrow = Bottom quarters
        if hasCommand && hasShift {
            switch keyCode {
            case KeyCode.leftArrow:
                return .snap(.bottomLeftQuarter)
            case KeyCode.rightArrow:
                return .snap(.bottomRightQuarter)
            default:
                return nil
            }
        }
        
        // Control + Option + Command + Arrow = Top quarters
        if hasCommand && !hasShift {
            switch keyCode {
            case KeyCode.leftArrow:
                return .snap(.topLeftQuarter)
            case KeyCode.rightArrow:
                return .snap(.topRightQuarter)
            default:
                return nil
            }
        }
        
        // Control + Option + Arrow/Return = Basic snapping (halves + maximize)
        if !hasCommand && !hasShift {
            switch keyCode {
            case KeyCode.leftArrow:
                return .smartDirection(.left)
            case KeyCode.rightArrow:
                return .smartDirection(.right)
            case KeyCode.upArrow:
                return .smartDirection(.up)
            case KeyCode.downArrow:
                return .smartDirection(.down)
            case KeyCode.returnKey, KeyCode.enter:
                return .snap(.maximize)
            default:
                return nil
            }
        }
        
        return nil
    }
    
    /// Perform the determined snap action
    private func performAction(_ action: SnapAction) {
        switch action {
        case .snap(let position):
            // Dismiss any showing picker first
            if SnapAssistController.shared.isShowingAssist {
                SnapAssistController.shared.dismiss()
            }
            log("Snapping to \(position.displayName)")
            windowManager.snapFrontmostWindow(to: position)
            postSnapNotification(direction: nil, position: position, isUnsnapToMiddle: false, isMinimize: false)
            
        case .smartDirection(let direction):
            // When picker is showing, use the stored snapped position (can't detect - MacSnap is frontmost)
            // Otherwise detect the current position
            let currentPosition: SnapPosition?
            if SnapAssistController.shared.isShowingAssist {
                currentPosition = SnapAssistController.shared.originalSnappedPosition
                log("Using stored position (picker showing): \(currentPosition?.displayName ?? "nil")")
            } else {
                currentPosition = windowManager.detectCurrentSnapPosition()
            }
            
            let result = SnapStateMachine.nextPosition(from: currentPosition, direction: direction)
            
            switch result {
            case .snap(let targetPosition):
                // Dismiss picker before snapping
                if SnapAssistController.shared.isShowingAssist {
                    SnapAssistController.shared.dismiss()
                }
                log("Smart \(direction): \(currentPosition?.displayName ?? "unsnapped") → \(targetPosition.displayName)")
                windowManager.snapFrontmostWindow(to: targetPosition)
                postSnapNotification(direction: direction, position: targetPosition, isUnsnapToMiddle: false, isMinimize: false)
                
            case .unsnapToMiddle:
                // unsnapToMiddle() handles picker dismissal internally
                log("Smart \(direction): \(currentPosition?.displayName ?? "unsnapped") → middle")
                windowManager.unsnapToMiddle()
                postSnapNotification(direction: direction, position: nil, isUnsnapToMiddle: true, isMinimize: false)
                
            case .minimize:
                // minimizeFrontmostWindow() handles picker dismissal internally
                log("Smart \(direction): \(currentPosition?.displayName ?? "unsnapped") → minimize")
                windowManager.minimizeFrontmostWindow()
                postSnapNotification(direction: direction, position: nil, isUnsnapToMiddle: false, isMinimize: true)
            }
            
        case .moveToMonitor(let direction):
            // Dismiss any showing picker first
            if SnapAssistController.shared.isShowingAssist {
                SnapAssistController.shared.dismiss()
            }
            log("Moving to \(direction) monitor")
            windowManager.moveFrontmostWindow(to: direction)
        }
    }
    
    /// Post notification about snap action for observers (e.g., onboarding tutorial)
    private func postSnapNotification(direction: SnapDirection?, position: SnapPosition?, isUnsnapToMiddle: Bool, isMinimize: Bool) {
        let info = SnapActionInfo(
            direction: direction,
            position: position,
            isUnsnapToMiddle: isUnsnapToMiddle,
            isMinimize: isMinimize
        )
        NotificationCenter.default.post(
            name: .snapActionPerformed,
            object: nil,
            userInfo: ["action": info]
        )
    }
}

// MARK: - Supporting Types

/// Actions that can be triggered by hotkeys
private enum SnapAction: CustomStringConvertible {
    case snap(SnapPosition)
    case smartDirection(SnapDirection)
    case moveToMonitor(MonitorDirection)
    
    var description: String {
        switch self {
        case .snap(let position):
            return "snap(\(position.displayName))"
        case .smartDirection(let direction):
            return "smart(\(direction))"
        case .moveToMonitor(let direction):
            return "moveToMonitor(\(direction))"
        }
    }
}

/// macOS key codes for arrow keys and return
private enum KeyCode {
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76  // Numpad enter
}
