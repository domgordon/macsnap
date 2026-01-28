import AppKit

/// A borderless window that displays window options for snap assist
/// Supports multi-zone display with active/waiting states
final class SnapAssistWindow: NSWindow {
    
    // MARK: - Layout Constants
    
    /// Shared layout constants for zone and thumbnail positioning
    enum Layout {
        /// Inset padding for visual breathing room between zones
        static let zonePadding: CGFloat = 10
        /// Inner margin within the blur area
        static let contentMargin: CGFloat = 32
        /// Total padding from zone edge to content (zonePadding + contentMargin)
        static let totalPadding: CGFloat = zonePadding + contentMargin
        /// Total padding for both sides (used in width/height calculations)
        static let totalPaddingBothSides: CGFloat = totalPadding * 2
        /// Spacing between thumbnails
        static let thumbnailSpacing: CGFloat = 12
    }
    
    // MARK: - Properties
    
    /// Windows available for selection (internal for keyboard extension)
    let windows: [WindowInfo]
    private let allPositions: [SnapPosition]
    private let activePosition: SnapPosition
    private let targetScreen: NSScreen
    private var thumbnailViews: [WindowThumbnailView] = []
    
    /// Currently selected index (internal for keyboard extension)
    var selectedIndex: Int = 0
    
    /// Zone views for layout calculation (internal for keyboard extension)
    private(set) var zoneViews: [NSView] = []
    
    var onWindowSelected: ((WindowInfo) -> Void)?
    var onDismiss: (() -> Void)?
    
    /// When true, ignore resignKey and appDidResignActive (during picker transitions)
    var ignoreResignEvents: Bool = false
    
    // MARK: - Initialization
    
    init(windows: [WindowInfo], allPositions: [SnapPosition], activePosition: SnapPosition, screen: NSScreen) {
        self.windows = windows
        self.allPositions = allPositions
        self.activePosition = activePosition
        self.targetScreen = screen
        
        // Window covers the entire screen
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        configureWindow()
        setupZones()
        updateSelection()
        
        // Animate in
        alphaValue = 0
        DispatchQueue.main.async { [weak self] in
            self?.animateIn()
        }
    }
    
    deinit {
        // Remove NotificationCenter observer to prevent memory leak
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Configuration
    
    private func configureWindow() {
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        
        // Critical for keyboard capture
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Dismiss when user interacts elsewhere
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidResignActive() {
        debugLog("SnapAssistWindow: appDidResignActive triggered (ignoreResignEvents=\(ignoreResignEvents))")
        guard !ignoreResignEvents else { return }
        dismissPicker()
    }
    
    override func resignKey() {
        debugLog("SnapAssistWindow: resignKey triggered (ignoreResignEvents=\(ignoreResignEvents))")
        super.resignKey()
        guard !ignoreResignEvents else { return }
        dismissPicker()
    }
    
    // MARK: - Zone Setup
    
    private func setupZones() {
        guard let contentView = contentView else { return }
        contentView.wantsLayer = true
        
        // Create overlay zones for all positions
        for position in allPositions {
            let zoneFrame = position.frame(in: targetScreen.visibleFrame, fullFrame: targetScreen.frame)
            // Convert to window coordinates (window covers full screen)
            let localFrame = convertScreenToWindow(zoneFrame)
            
            let isActive = (position == activePosition)
            let zoneView = createZoneView(frame: localFrame, isActive: isActive)
            contentView.addSubview(zoneView)
            zoneViews.append(zoneView)
            
            // Add thumbnails only to active zone
            if isActive {
                setupThumbnails(in: zoneView, frame: localFrame)
            }
        }
    }
    
    private func createZoneView(frame: NSRect, isActive: Bool) -> NSView {
        let containerView = NSView(frame: frame)
        containerView.wantsLayer = true
        
        // Inset padding for visual breathing room between zones
        let insetBounds = containerView.bounds.insetBy(dx: Layout.zonePadding, dy: Layout.zonePadding)
        
        // Blur background with native macOS styling
        let blurView = NSVisualEffectView(frame: insetBounds)
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.layer?.cornerRadius = 14
        blurView.layer?.masksToBounds = true
        
        // Subtle inner border for definition (native macOS panel style)
        blurView.layer?.borderWidth = 0.5
        blurView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        
        // Soft shadow for depth
        containerView.layer?.shadowColor = NSColor.black.cgColor
        containerView.layer?.shadowOpacity = 0.25
        containerView.layer?.shadowRadius = 20
        containerView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        
        containerView.addSubview(blurView)
        
        return containerView
    }
    
    private func setupThumbnails(in zoneView: NSView, frame: NSRect) {
        // Create scroll view for thumbnails
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        
        let containerView = FlippedView()
        containerView.wantsLayer = true
        scrollView.documentView = containerView
        
        // Content padding within the blur area
        scrollView.frame = NSRect(
            x: Layout.totalPadding,
            y: Layout.totalPadding,
            width: zoneView.bounds.width - Layout.totalPaddingBothSides,
            height: zoneView.bounds.height - Layout.totalPaddingBothSides
        )
        scrollView.autoresizingMask = [.width, .height]
        zoneView.addSubview(scrollView)
        
        // Create thumbnails
        let availableWidth = scrollView.frame.width - 40
        let thumbnailWidth = WindowThumbnailView.totalSize.width
        let thumbnailHeight = WindowThumbnailView.totalSize.height
        
        let columns = max(1, Int((availableWidth + Layout.thumbnailSpacing) / (thumbnailWidth + Layout.thumbnailSpacing)))
        let rows = (windows.count + columns - 1) / columns
        
        let totalWidth = CGFloat(columns) * thumbnailWidth + CGFloat(columns - 1) * Layout.thumbnailSpacing
        let totalHeight = CGFloat(rows) * thumbnailHeight + CGFloat(rows - 1) * Layout.thumbnailSpacing
        
        containerView.frame = NSRect(x: 0, y: 0, width: max(totalWidth, availableWidth), height: totalHeight)
        
        for (index, windowInfo) in windows.enumerated() {
            let row = index / columns
            let col = index % columns
            
            let x = CGFloat(col) * (thumbnailWidth + Layout.thumbnailSpacing)
            let y = CGFloat(row) * (thumbnailHeight + Layout.thumbnailSpacing)
            
            debugLog("SnapAssistWindow: Creating thumbnail[\(index)] for '\(windowInfo.title)' at \(windowInfo.frame)")
            let thumbnailView = WindowThumbnailView(windowInfo: windowInfo)
            thumbnailView.frame = NSRect(x: x, y: y, width: thumbnailWidth, height: thumbnailHeight)
            thumbnailView.onSelect = { [weak self] info in
                debugLog("SnapAssistWindow: Thumbnail clicked for '\(info.title)' at \(info.frame)")
                self?.selectWindow(info)
            }
            
            containerView.addSubview(thumbnailView)
            thumbnailViews.append(thumbnailView)
        }
    }
    
    private func convertScreenToWindow(_ screenRect: NSRect) -> NSRect {
        // Convert screen coordinates to window coordinates
        // Window frame is at screen origin, so just offset by window origin
        return NSRect(
            x: screenRect.origin.x - frame.origin.x,
            y: screenRect.origin.y - frame.origin.y,
            width: screenRect.width,
            height: screenRect.height
        )
    }
    
    // MARK: - Animation
    
    private func animateIn() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }) {
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func animateOut(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }) {
            completion()
        }
    }
    
    // MARK: - Selection (internal for keyboard extension)
    
    /// Update visual selection state of thumbnails
    func updateSelection() {
        for (index, view) in thumbnailViews.enumerated() {
            view.isSelected = (index == selectedIndex)
        }
        
        if selectedIndex < thumbnailViews.count {
            // Find the scroll view and scroll to selected
            if let scrollView = thumbnailViews.first?.superview?.superview as? NSScrollView {
                let selectedView = thumbnailViews[selectedIndex]
                scrollView.contentView.scrollToVisible(selectedView.frame)
            }
        }
    }
    
    /// Select a window and trigger the callback
    func selectWindow(_ windowInfo: WindowInfo) {
        // Clear handlers to prevent re-entry during transition
        debugLog("SnapAssistWindow: selectWindow called, clearing handlers")
        onDismiss = nil
        let callback = onWindowSelected
        onWindowSelected = nil
        
        // Start window snap IMMEDIATELY (parallel with fade-out for snappy feel)
        debugLog("SnapAssistWindow: triggering callback immediately (parallel)")
        callback?(windowInfo)
        
        // Fade out picker UI in parallel - no completion action needed
        // Controller handles window lifecycle during transition
        animateOut { }
    }
    
    func dismissPicker() {
        animateOut { [weak self] in
            self?.onDismiss?()
            self?.close()
        }
    }
    
    // MARK: - Keyboard Handling
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(self)
    }
    
    override func keyDown(with event: NSEvent) {
        handleKeyDown(event)
    }
    
    // MARK: - Mouse Handling
    
    override func mouseDown(with event: NSEvent) {
        let locationInWindow = event.locationInWindow
        
        // Check if click is inside any zone
        var clickedInsideZone = false
        for zoneView in zoneViews {
            let locationInZone = zoneView.convert(locationInWindow, from: nil)
            if zoneView.bounds.contains(locationInZone) {
                clickedInsideZone = true
                break
            }
        }
        
        if !clickedInsideZone {
            dismissPicker()
        }
    }
}

// MARK: - Flipped View (for top-to-bottom layout)

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
