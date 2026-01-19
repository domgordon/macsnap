import AppKit

/// A borderless window that displays window options for snap assist
/// Supports multi-zone display with active/waiting states
final class SnapAssistWindow: NSWindow {
    
    // MARK: - Properties
    
    private let windows: [WindowInfo]
    private let allPositions: [SnapPosition]
    private let activePosition: SnapPosition
    private let targetScreen: NSScreen
    private var thumbnailViews: [WindowThumbnailView] = []
    private var selectedIndex: Int = 0
    private var zoneViews: [NSView] = []
    
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
        let zonePadding: CGFloat = 10
        let insetBounds = containerView.bounds.insetBy(dx: zonePadding, dy: zonePadding)
        
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
        
        // Content padding within the blur area (zone padding + inner content margin)
        let zonePadding: CGFloat = 10  // Must match createZoneView
        let contentMargin: CGFloat = 32  // Inner margin within blur
        let totalPadding = zonePadding + contentMargin
        
        scrollView.frame = NSRect(
            x: totalPadding,
            y: totalPadding,
            width: zoneView.bounds.width - (totalPadding * 2),
            height: zoneView.bounds.height - (totalPadding * 2)
        )
        scrollView.autoresizingMask = [.width, .height]
        zoneView.addSubview(scrollView)
        
        // Create thumbnails
        let availableWidth = scrollView.frame.width - 40
        let thumbnailWidth = WindowThumbnailView.totalSize.width
        let thumbnailHeight = WindowThumbnailView.totalSize.height
        let spacing: CGFloat = 12
        
        let columns = max(1, Int((availableWidth + spacing) / (thumbnailWidth + spacing)))
        let rows = (windows.count + columns - 1) / columns
        
        let totalWidth = CGFloat(columns) * thumbnailWidth + CGFloat(columns - 1) * spacing
        let totalHeight = CGFloat(rows) * thumbnailHeight + CGFloat(rows - 1) * spacing
        
        containerView.frame = NSRect(x: 0, y: 0, width: max(totalWidth, availableWidth), height: totalHeight)
        
        for (index, windowInfo) in windows.enumerated() {
            let row = index / columns
            let col = index % columns
            
            let x = CGFloat(col) * (thumbnailWidth + spacing)
            let y = CGFloat(row) * (thumbnailHeight + spacing)
            
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
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }) {
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func animateOut(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }) {
            completion()
        }
    }
    
    // MARK: - Selection
    
    private func updateSelection() {
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
    
    private func selectWindow(_ windowInfo: WindowInfo) {
        // Clear dismiss handler before animation to prevent resignKey from triggering dismiss
        // during the transition to the next picker
        debugLog("SnapAssistWindow: selectWindow called, clearing onDismiss")
        onDismiss = nil
        
        // Capture callback before animation (in case it gets cleared)
        let callback = onWindowSelected
        onWindowSelected = nil  // Prevent double-calls
        
        animateOut { [weak self] in
            debugLog("SnapAssistWindow: animateOut complete, calling callback")
            // Call the callback - controller handles window lifecycle (including closing)
            callback?(windowInfo)
            // Don't call close() here - controller will close this window during transition
        }
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
        guard !windows.isEmpty else {
            dismissPicker()
            return
        }
        
        switch event.keyCode {
        case 53:  // Escape
            dismissPicker()
            
        case 36, 76:  // Return, Enter
            if selectedIndex < windows.count {
                let selected = windows[selectedIndex]
                debugLog("SnapAssistWindow: Enter pressed, selectedIndex=\(selectedIndex), window='\(selected.title)' at \(selected.frame)")
                selectWindow(selected)
            }
            
        case 123:  // Left arrow
            moveSelection(by: -1)
            
        case 124:  // Right arrow
            moveSelection(by: 1)
            
        case 125:  // Down arrow
            moveSelectionVertical(by: 1)
            
        case 126:  // Up arrow
            moveSelectionVertical(by: -1)
            
        case 48:  // Tab
            moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            
        default:
            break
        }
    }
    
    private func moveSelection(by delta: Int) {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + windows.count) % windows.count
        updateSelection()
    }
    
    private func moveSelectionVertical(by rowDelta: Int) {
        guard !windows.isEmpty else { return }
        guard let firstZone = zoneViews.first else { return }
        
        // Must match setupThumbnails padding calculation
        let totalPadding: CGFloat = (10 + 32) * 2  // zonePadding + contentMargin, both sides
        let availableWidth = firstZone.bounds.width - totalPadding
        let thumbnailWidth = WindowThumbnailView.totalSize.width
        let spacing: CGFloat = 12
        let columns = max(1, Int((availableWidth + spacing) / (thumbnailWidth + spacing)))
        
        let newIndex = selectedIndex + (rowDelta * columns)
        if newIndex >= 0 && newIndex < windows.count {
            selectedIndex = newIndex
            updateSelection()
        }
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
