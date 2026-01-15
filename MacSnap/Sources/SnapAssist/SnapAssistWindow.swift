import AppKit

/// A borderless window that displays window options for snap assist
/// Covers the "empty" half of the screen after snapping
final class SnapAssistWindow: NSWindow {
    
    // MARK: - Properties
    
    private let windows: [WindowInfo]
    private let targetPosition: SnapPosition
    private var thumbnailViews: [WindowThumbnailView] = []
    private var selectedIndex: Int = 0
    
    var onWindowSelected: ((WindowInfo) -> Void)?
    var onDismiss: (() -> Void)?
    
    // MARK: - UI Components
    
    private let blurView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
        return view
    }()
    
    private let scrollView: NSScrollView = {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        return scroll
    }()
    
    private let containerView: FlippedView = {
        let view = FlippedView()
        view.wantsLayer = true
        return view
    }()
    
    // MARK: - Initialization
    
    init(windows: [WindowInfo], targetPosition: SnapPosition, frame: NSRect) {
        self.windows = windows
        self.targetPosition = targetPosition
        
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        configureWindow()
        setupUI()
        createThumbnails()
        updateSelection()
        
        // Animate in
        alphaValue = 0
        DispatchQueue.main.async { [weak self] in
            self?.animateIn()
        }
    }
    
    // MARK: - Configuration
    
    private func configureWindow() {
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
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
        // User clicked on another app
        dismiss()
    }
    
    override func resignKey() {
        super.resignKey()
        // User clicked elsewhere or another window became key
        dismiss()
    }
    
    private func setupUI() {
        guard let contentView = contentView else { return }
        
        contentView.wantsLayer = true
        
        // Blur background
        contentView.addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        
        // Scroll view for thumbnails
        blurView.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = containerView
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            blurView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            blurView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            blurView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            scrollView.topAnchor.constraint(equalTo: blurView.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: blurView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: blurView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: blurView.bottomAnchor, constant: -20),
        ])
    }
    
    private func createThumbnails() {
        let availableWidth = frame.width - 80
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
            
            let thumbnailView = WindowThumbnailView(windowInfo: windowInfo)
            thumbnailView.frame = NSRect(x: x, y: y, width: thumbnailWidth, height: thumbnailHeight)
            thumbnailView.onSelect = { [weak self] info in
                self?.selectWindow(info)
            }
            
            containerView.addSubview(thumbnailView)
            thumbnailViews.append(thumbnailView)
        }
    }
    
    // MARK: - Animation
    
    private func animateIn() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08  // Snappy appearance
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
            let selectedView = thumbnailViews[selectedIndex]
            scrollView.contentView.scrollToVisible(selectedView.frame)
        }
    }
    
    private func selectWindow(_ windowInfo: WindowInfo) {
        // Animate out, then trigger action
        animateOut { [weak self] in
            self?.onWindowSelected?(windowInfo)
            self?.close()
        }
    }
    
    func dismiss() {
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
        // Ensure we're the first responder for keyboard events
        makeFirstResponder(self)
    }
    
    override func keyDown(with event: NSEvent) {
        guard !windows.isEmpty else {
            dismiss()
            return
        }
        
        switch event.keyCode {
        case 53:  // Escape
            dismiss()
            
        case 36, 76:  // Return, Enter
            if selectedIndex < windows.count {
                selectWindow(windows[selectedIndex])
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
        
        let availableWidth = frame.width - 80
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
        let locationInBlur = blurView.convert(locationInWindow, from: nil)
        
        if !blurView.bounds.contains(locationInBlur) {
            dismiss()
        }
    }
}

// MARK: - Flipped View (for top-to-bottom layout)

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
