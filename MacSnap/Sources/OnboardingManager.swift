import Foundation

/// Manages first-run onboarding state
final class OnboardingManager {
    
    static let shared = OnboardingManager()
    
    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    
    private init() {}
    
    /// Whether this is the first launch (onboarding not yet completed)
    var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
    }
    
    /// Mark onboarding as complete
    func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.synchronize()  // Force sync to disk immediately
        debugLog("OnboardingManager: Onboarding marked complete")
    }
    
    /// Reset onboarding state (for testing or "Show Welcome" menu item)
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
        debugLog("OnboardingManager: Onboarding state reset")
    }
}
