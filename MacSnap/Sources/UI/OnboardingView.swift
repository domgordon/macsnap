import SwiftUI
import AppKit
import Combine

/// Arrow key directions for tutorial
enum ArrowKey: Equatable {
    case left, right, up, down
    
    var keyCode: UInt16 {
        switch self {
        case .left: return 123
        case .right: return 124
        case .up: return 126
        case .down: return 125
        }
    }
    
    static func from(keyCode: UInt16) -> ArrowKey? {
        switch keyCode {
        case 123: return .left
        case 124: return .right
        case 126: return .up
        case 125: return .down
        default: return nil
        }
    }
}

/// Steps in the onboarding flow
enum OnboardingStep: Equatable {
    case requestingPermission
    case tutorialStep1_left
    case tutorialStep2_picker    // Conditional: only when other windows exist
    case tutorialStep3_center
    case tutorialStep4_up
    case tutorialStep5_center
    case complete
    
    var title: String {
        switch self {
        case .requestingPermission:
            return "MacSnap"
        case .tutorialStep1_left:
            return "Snap Left"
        case .tutorialStep2_picker:
            return "Fill the Other Half"
        case .tutorialStep3_center:
            return "Return to Center"
        case .tutorialStep4_up:
            return "Maximize"
        case .tutorialStep5_center:
            return "Return to Center"
        case .complete:
            return "You're All Set!"
        }
    }
    
    var description: String {
        switch self {
        case .requestingPermission:
            return "Control + Option + Arrow Keys to snap windows"
        case .tutorialStep1_left:
            return "Snap windows to the left half"
        case .tutorialStep2_picker:
            return "Select a window for the right side"
        case .tutorialStep3_center:
            return "Return to original size"
        case .tutorialStep4_up:
            return "Fill the entire screen"
        case .tutorialStep5_center:
            return "Return to original size"
        case .complete:
            return "MacSnap is running in your menu bar"
        }
    }
    
    var expectedArrow: ArrowKey? {
        switch self {
        case .tutorialStep1_left: return .left
        case .tutorialStep3_center: return .right
        case .tutorialStep4_up: return .up
        case .tutorialStep5_center: return .down
        default: return nil
        }
    }
    
    var snapPosition: SnapPosition? {
        switch self {
        case .tutorialStep1_left: return .leftHalf
        case .tutorialStep3_center: return nil // Uses centerWindow
        case .tutorialStep4_up: return .maximize
        case .tutorialStep5_center: return nil // Uses centerWindow
        default: return nil
        }
    }
    
    /// Get next step - requires context about whether picker step is included
    /// Use OnboardingView.nextStep(from:) instead for dynamic behavior
    var nextStep: OnboardingStep? {
        switch self {
        case .requestingPermission: return .tutorialStep1_left
        case .tutorialStep1_left: return .tutorialStep2_picker  // Default assumes picker exists
        case .tutorialStep2_picker: return .tutorialStep3_center
        case .tutorialStep3_center: return .tutorialStep4_up
        case .tutorialStep4_up: return .tutorialStep5_center
        case .tutorialStep5_center: return .complete
        case .complete: return nil
        }
    }
    
    var isTutorialStep: Bool {
        switch self {
        case .tutorialStep1_left, .tutorialStep2_picker, .tutorialStep3_center, .tutorialStep4_up, .tutorialStep5_center:
            return true
        default:
            return false
        }
    }
    
    var usesCenterWindow: Bool {
        switch self {
        case .tutorialStep3_center, .tutorialStep5_center:
            return true
        default:
            return false
        }
    }
    
    /// Whether this step is the picker step
    var isPickerStep: Bool {
        self == .tutorialStep2_picker
    }
}

/// SwiftUI onboarding view for first-run experience
struct OnboardingView: View {
    
    // Permission state
    @State private var hasPermissions: Bool = WindowManager.shared.hasAccessibilityPermissions
    @State private var lastKnownPermissionState: Bool = WindowManager.shared.hasAccessibilityPermissions
    @State private var timerCancellable: Timer?
    
    // Tutorial state
    @State private var currentStep: OnboardingStep = .requestingPermission
    @State private var hasOtherWindows: Bool = false  // Determines if picker step is included
    @State private var cameFromPickerStep: Bool = false  // True if user just selected from picker
    @State private var pickerFallbackTimer: Timer? = nil  // Fallback if picker doesn't appear
    
    // Key press tracking
    @State private var isControlPressed: Bool = false
    @State private var isOptionPressed: Bool = false
    @State private var pressedArrowKey: ArrowKey? = nil
    @State private var keyMonitor: Any? = nil
    
    // Notification publishers
    private let snapActionPublisher = NotificationCenter.default.publisher(for: .snapActionPerformed)
    private let snapAssistDismissedPublisher = NotificationCenter.default.publisher(for: .snapAssistDismissed)
    
    
    var onComplete: (() -> Void)?
    
    var body: some View {
        Group {
            switch currentStep {
            case .requestingPermission:
                permissionRequestView
            case .tutorialStep1_left, .tutorialStep2_picker, .tutorialStep3_center, .tutorialStep4_up, .tutorialStep5_center:
                tutorialStepView
            case .complete:
                completionView
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .onReceive(snapActionPublisher) { notification in
            guard let info = notification.userInfo?["action"] as? SnapActionInfo else { return }
            handleSnapAction(info)
        }
        .onReceive(snapAssistDismissedPublisher) { _ in
            handlePickerDismissed()
        }
    }
    
    // MARK: - Permission Request View
    
    private var permissionRequestView: some View {
        VStack(spacing: 0) {
            // Top spacing - slightly less than tutorial to account for icon
            Spacer()
                .frame(height: 24)
            
            // Icon
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.primary.opacity(0.5))
            
            Spacer()
                .frame(height: 14)
            
            // Title (same font as tutorial steps - title lands at ~74pt from top)
            Text("MacSnap")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            
            Spacer()
                .frame(height: 8)
            
            // Keyboard shortcut hint (same font as tutorial descriptions)
            Text("⌃ ⌥ Arrow Keys")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            Spacer()
                .frame(height: 28)
            
            // Permission status
            permissionCard
            
            Spacer()
        }
    }
    
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(hasPermissions ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                
                Text(hasPermissions ? "Ready" : "Accessibility access needed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            
            if !hasPermissions {
                Text("MacSnap needs permission to move windows.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button(action: { AppUtils.openAccessibilitySettings() }) {
                    Text("Open System Settings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 28)
    }
    
    // MARK: - Tutorial Step View
    
    private var tutorialStepView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 36)
            
            // Step indicator
            HStack(spacing: 6) {
                ForEach(tutorialSteps, id: \.self) { step in
                    Circle()
                        .fill(stepIndicatorColor(for: step))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 28)
            
            // Title
            Text(currentStep.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            
            Spacer()
                .frame(height: 8)
            
            // Description
            Text(currentStep.description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            Spacer()
                .frame(height: 36)
            
            // Show different content for picker step vs keyboard steps
            if currentStep.isPickerStep {
                pickerStepContent
            } else {
                VStack(spacing: 16) {
                    // Show "click this window" hint after picker step
                    if shouldShowClickWindowHint {
                        clickWindowHint
                    }
                    
                    keyboardShortcutView
                }
            }
            
            Spacer()
        }
    }
    
    /// Whether to show the "click this window" hint
    private var shouldShowClickWindowHint: Bool {
        currentStep == .tutorialStep3_center && cameFromPickerStep
    }
    
    /// Hint to click this window after using picker
    private var clickWindowHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
            
            Text("Click this window first")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
    
    /// Content shown during the picker step (no keyboard shortcut)
    private var pickerStepContent: some View {
        VStack(spacing: 12) {
            // Arrow pointing to the picker
            Image(systemName: "arrow.right.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            
            Text("Click a window in the picker")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }
    
    private func stepIndicatorColor(for step: OnboardingStep) -> Color {
        if step == currentStep {
            return .accentColor
        } else if stepIndex(step) < stepIndex(currentStep) {
            return .green
        } else {
            return .primary.opacity(0.15)
        }
    }
    
    private func stepIndex(_ step: OnboardingStep) -> Int {
        tutorialSteps.firstIndex(of: step) ?? -1
    }
    
    private var keyboardShortcutView: some View {
        HStack(spacing: 6) {
            KeyCapView(label: "⌃", sublabel: "control", isHighlighted: isControlPressed)
            KeyCapView(label: "⌥", sublabel: "option", isHighlighted: isOptionPressed)
            KeyCapView(label: arrowSymbol, sublabel: arrowLabel, isHighlighted: isCorrectArrowPressed)
        }
    }
    
    private var isCorrectArrowPressed: Bool {
        guard let expected = currentStep.expectedArrow,
              let pressed = pressedArrowKey else {
            return false
        }
        return pressed == expected
    }
    
    private var arrowSymbol: String {
        switch currentStep {
        case .tutorialStep1_left: return "←"
        case .tutorialStep3_center: return "→"
        case .tutorialStep4_up: return "↑"
        case .tutorialStep5_center: return "↓"
        default: return ""
        }
    }
    
    private var arrowLabel: String {
        switch currentStep {
        case .tutorialStep1_left: return "left"
        case .tutorialStep3_center: return "right"
        case .tutorialStep4_up: return "up"
        case .tutorialStep5_center: return "down"
        default: return ""
        }
    }
    
    
    // MARK: - Completion View
    
    private var completionView: some View {
        VStack(spacing: 0) {
            // Top spacing - matches permission view for consistent icon position
            Spacer()
                .frame(height: 24)
            
            // Success icon (same size as permission view icon)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            
            Spacer()
                .frame(height: 14)
            
            // Title (same font as other views - title lands at ~74pt from top)
            Text(currentStep.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            
            Spacer()
                .frame(height: 28)
            
            // Menu bar preview
            menuBarPreview
            
            Spacer()
                .frame(height: 10)
            
            Text("Find MacSnap in your menu bar")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Get Started button
            Button(action: completeOnboarding) {
                Text("Get Started")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 28)
        }
    }
    
    /// Visual representation of the menu bar with MacSnap icon
    private var menuBarPreview: some View {
        HStack(spacing: 0) {
            // Left side placeholder items
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 20, height: 8)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 28, height: 8)
            }
            
            Spacer()
            
            // Right side with MacSnap icon highlighted
            HStack(spacing: 6) {
                // Other menu bar icons (placeholder circles)
                Circle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 14, height: 14)
                
                // MacSnap icon (highlighted)
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 26, height: 22)
                    
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                
                // Time placeholder
                Text("12:00")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.4))
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 240)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Lifecycle
    
    private func onAppear() {
        // Silently enable launch at login
        AppUtils.setLaunchAtLogin(true)
        
        // Check permissions directly from WindowManager (not @State which may be stale)
        let permissionsGranted = WindowManager.shared.hasAccessibilityPermissions
        hasPermissions = permissionsGranted
        
        // If permissions already granted, start tutorial immediately
        if permissionsGranted {
            debugLog("OnboardingView: Permissions already granted on appear, starting tutorial")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.currentStep == .requestingPermission {
                    self.startTutorial()
                }
            }
        } else {
            // Start polling timer for permission changes (only if not already granted)
            timerCancellable = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                self.checkPermissions()
            }
        }
    }
    
    private func onDisappear() {
        timerCancellable?.invalidate()
        timerCancellable = nil
        pickerFallbackTimer?.invalidate()
        pickerFallbackTimer = nil
        stopKeyMonitoring()
    }
    
    private func checkPermissions() {
        let currentState = WindowManager.shared.hasAccessibilityPermissions
        hasPermissions = currentState
        
        // Detect permission state change: not granted -> granted
        if !lastKnownPermissionState && currentState {
            debugLog("OnboardingView: Permissions just granted, starting tutorial")
            startTutorial()
        }
        
        lastKnownPermissionState = currentState
    }
    
    // MARK: - Tutorial Control
    
    private func startTutorial() {
        // Stop polling - we have permissions now
        timerCancellable?.invalidate()
        timerCancellable = nil
        
        // Start the hotkey manager so shortcuts work going forward
        HotkeyManager.shared.start()
        
        // Check if there are other windows available for the picker step
        // This determines whether we show 4 or 5 tutorial steps
        if let screen = NSScreen.main {
            let otherWindows = WindowManager.shared.getOtherWindows(excludingWindowID: nil, on: screen)
            hasOtherWindows = !otherWindows.isEmpty
            debugLog("OnboardingView: Other windows available: \(hasOtherWindows) (\(otherWindows.count) windows)")
        }
        
        // Prepare the window for tutorial (make it larger)
        OnboardingWindowController.shared.prepareForTutorial()
        
        // Start key monitoring for the tutorial
        startKeyMonitoring()
        
        // Advance to first tutorial step
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.currentStep = .tutorialStep1_left
            }
        }
    }
    
    private func advanceToNextStep() {
        guard let nextStep = getNextStep(from: currentStep) else {
            return
        }
        
        // Reset key states
        pressedArrowKey = nil
        
        // Reset "came from picker" flag when leaving step 3
        if currentStep == .tutorialStep3_center {
            cameFromPickerStep = false
        }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = nextStep
        }
        
        // Start fallback timer when entering picker step
        if nextStep == .tutorialStep2_picker {
            startPickerFallbackTimer()
        }
        
        // If complete, stop key monitoring and flash menu bar icon
        if nextStep == .complete {
            stopKeyMonitoring()
            // Flash the menu bar icon to draw attention to it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                StatusBarController.shared?.flashIcon(times: 5)
            }
        }
    }
    
    /// Get the next step, accounting for whether picker step is included
    private func getNextStep(from step: OnboardingStep) -> OnboardingStep? {
        switch step {
        case .requestingPermission:
            return .tutorialStep1_left
        case .tutorialStep1_left:
            // Skip picker step if no other windows
            return hasOtherWindows ? .tutorialStep2_picker : .tutorialStep3_center
        case .tutorialStep2_picker:
            return .tutorialStep3_center
        case .tutorialStep3_center:
            return .tutorialStep4_up
        case .tutorialStep4_up:
            return .tutorialStep5_center
        case .tutorialStep5_center:
            return .complete
        case .complete:
            return nil
        }
    }
    
    /// Get the list of tutorial steps to show in the indicator
    private var tutorialSteps: [OnboardingStep] {
        if hasOtherWindows {
            return [.tutorialStep1_left, .tutorialStep2_picker, .tutorialStep3_center, .tutorialStep4_up, .tutorialStep5_center]
        } else {
            return [.tutorialStep1_left, .tutorialStep3_center, .tutorialStep4_up, .tutorialStep5_center]
        }
    }
    
    private func completeOnboarding() {
        OnboardingManager.shared.markOnboardingComplete()
        onComplete?()
    }
    
    // MARK: - Key Monitoring
    
    private func startKeyMonitoring() {
        // Monitor for modifier keys (flagsChanged) only - arrow keys are handled by HotkeyManager
        // Snap action notifications are handled via .onReceive modifier in body
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            self.handleKeyEvent(event)
            return event
        }
        
        debugLog("OnboardingView: Started key monitoring for tutorial")
    }
    
    private func stopKeyMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        debugLog("OnboardingView: Stopped key monitoring")
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        // Update modifier key states (arrow keys are handled via snap notification)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        withAnimation(.easeInOut(duration: 0.1)) {
            isControlPressed = flags.contains(.control)
            isOptionPressed = flags.contains(.option)
        }
    }
    
    /// Handle snap action notification from HotkeyManager
    private func handleSnapAction(_ info: SnapActionInfo) {
        guard currentStep.isTutorialStep else { return }
        
        // Update arrow key highlight based on direction
        if let direction = info.direction {
            let arrow: ArrowKey? = {
                switch direction {
                case .left: return .left
                case .right: return .right
                case .up: return .up
                case .down: return .down
                }
            }()
            
            withAnimation(.easeInOut(duration: 0.1)) {
                pressedArrowKey = arrow
            }
            
            // Clear the highlight after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    self.pressedArrowKey = nil
                }
            }
        }
        
        // Check if this action matches what the tutorial expects
        checkForCorrectAction(info)
    }
    
    /// Handle picker dismissed notification - advances picker step
    private func handlePickerDismissed() {
        // Only advance if we're on the picker step
        guard currentStep == .tutorialStep2_picker else { return }
        
        // Cancel fallback timer since picker was properly dismissed
        pickerFallbackTimer?.invalidate()
        pickerFallbackTimer = nil
        
        // Mark that we came from picker (for "click this window" hint)
        cameFromPickerStep = true
        
        debugLog("OnboardingView: Picker dismissed during picker step, advancing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.advanceToNextStep()
        }
    }
    
    /// Start fallback timer for picker step in case picker doesn't appear
    private func startPickerFallbackTimer() {
        pickerFallbackTimer?.invalidate()
        
        // If picker doesn't show within 1.5s (picker delay is 0.5s + buffer), advance anyway
        pickerFallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [self] _ in
            guard currentStep == .tutorialStep2_picker else { return }
            
            // Check if picker is actually showing
            if !SnapAssistController.shared.isShowingAssist {
                debugLog("OnboardingView: Picker fallback - picker didn't appear, advancing")
                // This is a success state (windows already clean-snapped), advance without "click this window" hint
                advanceToNextStep()
            }
        }
    }
    
    private func checkForCorrectAction(_ info: SnapActionInfo) {
        guard currentStep.isTutorialStep else { return }
        guard let expectedArrow = currentStep.expectedArrow else { return }
        
        // Map expected arrow to expected direction
        let expectedDirection: SnapDirection = {
            switch expectedArrow {
            case .left: return .left
            case .right: return .right
            case .up: return .up
            case .down: return .down
            }
        }()
        
        // Check if the direction matches
        guard info.direction == expectedDirection else { return }
        
        // For center steps (step 2 and 4), we expect unsnapToMiddle
        if currentStep.usesCenterWindow {
            guard info.isUnsnapToMiddle else { return }
            debugLog("OnboardingView: Correct unsnap for step \(currentStep)")
            // HotkeyManager already moved the window, just advance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.advanceToNextStep()
            }
        } else if let expectedPosition = currentStep.snapPosition {
            // For snap steps, check if the position matches
            guard info.position == expectedPosition else { return }
            debugLog("OnboardingView: Correct snap for step \(currentStep)")
            // HotkeyManager already snapped the window
            // Delay advancement to allow picker to appear (picker delay is 0.5s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.advanceToNextStep()
            }
        }
    }
    
}

// MARK: - Key Cap View

/// Styled keyboard key visualization with highlight support
struct KeyCapView: View {
    let label: String
    let sublabel: String
    var isHighlighted: Bool = false
    
    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isHighlighted ? .white : .primary.opacity(0.85))
            Text(sublabel)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(isHighlighted ? .white.opacity(0.7) : .secondary)
        }
        .frame(width: 50, height: 50)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHighlighted ? Color.accentColor : Color.primary.opacity(0.05))
                .shadow(color: .black.opacity(isHighlighted ? 0.15 : 0.04), radius: 1, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isHighlighted ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            OnboardingView()
                .previewDisplayName("Permission Request")
            
            OnboardingView()
                .previewDisplayName("Tutorial Step")
        }
    }
}
#endif
