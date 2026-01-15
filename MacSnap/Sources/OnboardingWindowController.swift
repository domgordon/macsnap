import AppKit
import SwiftUI

/// Window controller to host the SwiftUI onboarding view
final class OnboardingWindowController: NSWindowController {
    
    /// Shared instance for showing the onboarding window
    static let shared = OnboardingWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "MacSnap"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        super.init(window: window)
        
        setupContent()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupContent() {
        let onboardingView = OnboardingView(onComplete: { [weak self] in
            self?.close()
        })
        
        let hostingView = NSHostingView(rootView: onboardingView)
        window?.contentView = hostingView
    }
    
    // MARK: - Public API
    
    /// Show the onboarding window
    func showWindow() {
        // Recreate content to reset state
        setupContent()
        
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        debugLog("OnboardingWindowController: Showing onboarding window")
    }
    
    /// Close the onboarding window
    override func close() {
        window?.orderOut(nil)
        debugLog("OnboardingWindowController: Closed onboarding window")
    }
}
