import AppKit
import ApplicationServices
import QuartzCore

// MARK: - Animation Constants (Single Source of Truth)

/// Centralized animation timing constants for consistent, snappy feel across the app.
/// All animation durations should reference these values to maintain consistency.
enum AnimationConfig {
    /// Duration for window snap/move animations (50ms)
    static let snapDuration: TimeInterval = 0.05
    
    /// Duration for UI fade in/out animations (50ms)
    static let fadeDuration: TimeInterval = 0.05
    
    /// Delay before keyboard focus is captured after showing picker (30ms)
    static let focusDelay: TimeInterval = 0.03
}

/// Frame-synchronized window animation using CVDisplayLink.
/// Provides smooth, jitter-free animations synced to the display refresh rate.
final class WindowAnimator {
    
    static let shared = WindowAnimator()
    
    // MARK: - Properties
    
    private var displayLink: CVDisplayLink?
    private var currentAnimation: AnimationState?
    private let lock = NSLock()
    
    private init() {}
    
    deinit {
        stopDisplayLink()
    }
    
    // MARK: - Animation State
    
    private struct AnimationState {
        let window: AXUIElement
        let startFrame: CGRect
        let endFrame: CGRect
        let startTime: CFTimeInterval
        let duration: CFTimeInterval
        var isComplete: Bool = false
    }
    
    // MARK: - Public API
    
    /// Animate a window from its current position to a target frame
    /// - Parameters:
    ///   - window: The AXUIElement window to animate
    ///   - from: Starting frame in NSScreen coordinates
    ///   - to: Target frame in NSScreen coordinates
    ///   - duration: Animation duration (defaults to AnimationConfig.snapDuration)
    func animate(window: AXUIElement, from: CGRect, to: CGRect, duration: TimeInterval = AnimationConfig.snapDuration) {
        lock.lock()
        defer { lock.unlock() }
        
        debugLog("WindowAnimator: Starting animation from \(from) to \(to)")
        
        // Cancel any existing animation
        currentAnimation?.isComplete = true
        
        // Start new animation
        currentAnimation = AnimationState(
            window: window,
            startFrame: from,
            endFrame: to,
            startTime: CACurrentMediaTime(),
            duration: duration
        )
        
        startDisplayLink()
    }
    
    // MARK: - Display Link
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        
        guard let displayLink = link else {
            // Fallback to timer-based animation if display link fails
            fallbackAnimate()
            return
        }
        
        self.displayLink = displayLink
        
        // Set up callback
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let animator = Unmanaged<WindowAnimator>.fromOpaque(userInfo).takeUnretainedValue()
            animator.displayLinkCallback()
            return kCVReturnSuccess
        }
        
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, userInfo)
        CVDisplayLinkStart(displayLink)
    }
    
    private func stopDisplayLink() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
    }
    
    private func displayLinkCallback() {
        lock.lock()
        guard var animation = currentAnimation, !animation.isComplete else {
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.stopDisplayLink()
            }
            return
        }
        lock.unlock()
        
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - animation.startTime
        let progress = min(elapsed / animation.duration, 1.0)
        
        // Ease-out cubic for snappy, decelerating motion
        let easedProgress = 1.0 - pow(1.0 - progress, 3.0)
        
        // Interpolate frame
        let currentFrame = interpolateFrame(
            from: animation.startFrame,
            to: animation.endFrame,
            progress: easedProgress
        )
        
        // Apply frame on main thread
        DispatchQueue.main.async { [weak self] in
            self?.setWindowFrame(animation.window, to: currentFrame)
        }
        
        // Check if complete
        if progress >= 1.0 {
            lock.lock()
            currentAnimation?.isComplete = true
            lock.unlock()
            
            DispatchQueue.main.async { [weak self] in
                self?.stopDisplayLink()
            }
        }
    }
    
    // MARK: - Fallback Animation
    
    /// Timer-based fallback if CVDisplayLink fails
    private func fallbackAnimate() {
        guard let animation = currentAnimation else { return }
        
        let steps = 6
        let stepDuration = animation.duration / Double(steps)
        
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            let easedProgress = 1.0 - pow(1.0 - progress, 3.0)
            
            let frame = interpolateFrame(
                from: animation.startFrame,
                to: animation.endFrame,
                progress: easedProgress
            )
            
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) { [weak self] in
                guard let self = self else { return }
                self.setWindowFrame(animation.window, to: frame)
            }
        }
    }
    
    // MARK: - Frame Interpolation
    
    private func interpolateFrame(from start: CGRect, to end: CGRect, progress: Double) -> CGRect {
        CGRect(
            x: start.origin.x + (end.origin.x - start.origin.x) * progress,
            y: start.origin.y + (end.origin.y - start.origin.y) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }
    
    // MARK: - Window Frame Setting
    
    private func setWindowFrame(_ window: AXUIElement, to frame: CGRect) {
        // Convert from NSScreen to AX coordinates
        let axFrame = CoordinateConverter.nsToAX(frame)
        
        // Set size first
        var size = frame.size
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            if sizeResult != .success {
                debugLog("WindowAnimator: Failed to set size, error: \(sizeResult.rawValue)")
            }
        }
        
        // Set position
        var position = axFrame.origin
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            let posResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
            if posResult != .success {
                debugLog("WindowAnimator: Failed to set position, error: \(posResult.rawValue)")
            }
        }
    }
}
