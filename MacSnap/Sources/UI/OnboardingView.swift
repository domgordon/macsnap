import SwiftUI

/// SwiftUI onboarding view for first-run experience
struct OnboardingView: View {
    
    @State private var hasPermissions: Bool = WindowManager.shared.hasAccessibilityPermissions
    @State private var lastKnownPermissionState: Bool = WindowManager.shared.hasAccessibilityPermissions
    @State private var isRestarting: Bool = false
    @State private var timerCancellable: Timer?
    
    var onComplete: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Top padding to clear titlebar
            Spacer()
                .frame(height: 32)
            
            // Icon
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.primary.opacity(0.7))
            
            Spacer()
                .frame(height: 20)
            
            // Title
            Text("MacSnap")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer()
                .frame(height: 32)
            
            // Keyboard shortcut hint
            VStack(spacing: 6) {
                Text("Control + Option + Arrow Keys")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Text("to snap windows")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
                .frame(height: 32)
            
            // Permission status
            permissionCard
            
            Spacer()
            
            // Restarting indicator (only shown when permissions just granted)
            if isRestarting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Restarting...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)
            } else {
                Spacer()
                    .frame(height: 24)
            }
        }
        .frame(width: 320, height: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
    }
    
    // MARK: - Permission Card
    
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(hasPermissions ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(hasPermissions ? "Ready to use" : "Accessibility access needed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            
            if !hasPermissions {
                Text("Enable MacSnap in System Settings to control window positions.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button(action: { AppUtils.openAccessibilitySettings() }) {
                    Text("Open System Settings")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 24)
    }
    
    // MARK: - Actions
    
    private func onAppear() {
        // Silently enable launch at login using consolidated AppUtils
        AppUtils.setLaunchAtLogin(true)
        
        // Start polling timer for permission changes (properly managed)
        timerCancellable = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
            self.checkPermissions()
        }
        
        // If permissions already granted, auto-complete after brief delay
        if hasPermissions {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if hasPermissions && !isRestarting {
                    OnboardingManager.shared.markOnboardingComplete()
                    onComplete?()
                }
            }
        }
    }
    
    private func onDisappear() {
        // Clean up timer to prevent memory leak
        timerCancellable?.invalidate()
        timerCancellable = nil
    }
    
    private func checkPermissions() {
        let currentState = WindowManager.shared.hasAccessibilityPermissions
        hasPermissions = currentState
        
        // Detect permission state change: not granted -> granted
        if !lastKnownPermissionState && currentState {
            debugLog("OnboardingView: Permissions just granted, triggering restart")
            triggerRestart()
        }
        
        lastKnownPermissionState = currentState
    }
    
    private func triggerRestart() {
        isRestarting = true
        OnboardingManager.shared.markOnboardingComplete()
        
        // Clean up timer before restart
        timerCancellable?.invalidate()
        timerCancellable = nil
        
        // Brief delay to show the "Restarting..." state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AppUtils.restartApp()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
#endif
