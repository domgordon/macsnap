import AppKit
import SwiftUI

/// Window controller to host the SwiftUI onboarding view
final class OnboardingWindowController: NSWindowController {
    
    /// Shared instance for showing the onboarding window
    static let shared = OnboardingWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
            styleMask: [.titled, .closable, .resizable],
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
    
    // MARK: - Tutorial Animation
    
    /// Prepare for tutorial mode (no size change needed)
    func prepareForTutorial() {
        // No size change needed - window stays at current size for seamless transition
        debugLog("OnboardingWindowController: Tutorial started")
    }
    
    /// Animate the onboarding window to a snap position
    func snapWindow(to position: SnapPosition, completion: (() -> Void)? = nil) {
        guard let window = self.window,
              let screen = window.screen else {
            completion?()
            return
        }
        
        let targetFrame = position.frame(
            in: screen.visibleFrame,
            fullFrame: screen.frame
        )
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
        }, completionHandler: {
            debugLog("OnboardingWindowController: Snapped to \(position.displayName)")
            completion?()
        })
    }
    
    /// Center the window on screen (preserves current size)
    func centerWindow() {
        guard let window = self.window,
              let screen = window.screen else { return }
        
        var frame = window.frame
        frame.origin.x = screen.visibleFrame.midX - frame.width / 2
        frame.origin.y = screen.visibleFrame.midY - frame.height / 2
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
        debugLog("OnboardingWindowController: Centered window")
    }
}
