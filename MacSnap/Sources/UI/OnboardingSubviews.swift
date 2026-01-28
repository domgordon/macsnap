import SwiftUI

// MARK: - Permission Card View

/// Card displaying permission status and action button
struct PermissionCardView: View {
    let hasPermissions: Bool
    
    var body: some View {
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
}

// MARK: - Menu Bar Preview View

/// Visual representation of the menu bar with MacSnap icon highlighted
struct MenuBarPreviewView: View {
    var body: some View {
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
}

// MARK: - Click Window Hint View

/// Hint to click the onboarding window after using picker
struct ClickWindowHintView: View {
    var body: some View {
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
}

// MARK: - Picker Step Content View

/// Content shown during the picker step (no keyboard shortcut)
struct PickerStepContentView: View {
    var body: some View {
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
}

// MARK: - Step Indicator View

/// Row of dots showing tutorial progress
struct StepIndicatorView: View {
    let steps: [OnboardingStep]
    let currentStep: OnboardingStep
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { step in
                Circle()
                    .fill(indicatorColor(for: step))
                    .frame(width: 6, height: 6)
            }
        }
    }
    
    private func indicatorColor(for step: OnboardingStep) -> Color {
        if step == currentStep {
            return .accentColor
        } else if stepIndex(step) < stepIndex(currentStep) {
            return .green
        } else {
            return .primary.opacity(0.15)
        }
    }
    
    private func stepIndex(_ step: OnboardingStep) -> Int {
        steps.firstIndex(of: step) ?? -1
    }
}

// MARK: - Keyboard Shortcut View

/// Visual display of the keyboard shortcut for current step
struct KeyboardShortcutView: View {
    let step: OnboardingStep
    let isControlPressed: Bool
    let isOptionPressed: Bool
    let isArrowPressed: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            KeyCapView(label: "⌃", sublabel: "control", isHighlighted: isControlPressed)
            KeyCapView(label: "⌥", sublabel: "option", isHighlighted: isOptionPressed)
            KeyCapView(label: arrowSymbol, sublabel: arrowLabel, isHighlighted: isArrowPressed)
        }
    }
    
    private var arrowSymbol: String {
        switch step {
        case .tutorialStep1_left: return "←"
        case .tutorialStep3_center: return "→"
        case .tutorialStep4_up: return "↑"
        case .tutorialStep5_center: return "↓"
        default: return ""
        }
    }
    
    private var arrowLabel: String {
        switch step {
        case .tutorialStep1_left: return "left"
        case .tutorialStep3_center: return "right"
        case .tutorialStep4_up: return "up"
        case .tutorialStep5_center: return "down"
        default: return ""
        }
    }
}
