import AppKit

/// A view displaying a window with app icon and title
/// Supports hover and selection states with macOS-native styling
final class WindowThumbnailView: NSView {
    
    // MARK: - Properties
    
    let windowInfo: WindowInfo
    
    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }
    
    var isHovered: Bool = false {
        didSet { updateAppearance() }
    }
    
    var onSelect: ((WindowInfo) -> Void)?
    
    // MARK: - UI Components
    
    private let containerView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        return view
    }()
    
    private let appIconView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()
    
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        return label
    }()
    
    private let highlightBorderLayer: CALayer = {
        let layer = CALayer()
        layer.cornerRadius = 12
        layer.borderWidth = 3
        layer.borderColor = NSColor.clear.cgColor
        return layer
    }()
    
    private var trackingArea: NSTrackingArea?
    
    // MARK: - Constants
    
    static let totalSize = CGSize(width: 140, height: 140)
    
    // MARK: - Initialization
    
    init(windowInfo: WindowInfo) {
        self.windowInfo = windowInfo
        super.init(frame: NSRect(origin: .zero, size: Self.totalSize))
        setupUI()
        configureContent()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        wantsLayer = true
        
        // Add highlight border layer
        layer?.addSublayer(highlightBorderLayer)
        
        // Container with blur
        addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // App icon (large, centered)
        containerView.addSubview(appIconView)
        appIconView.translatesAutoresizingMaskIntoConstraints = false
        
        // Title below icon
        containerView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Container fills view with small margin
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            
            // Large app icon centered
            appIconView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            appIconView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            appIconView.widthAnchor.constraint(equalToConstant: 64),
            appIconView.heightAnchor.constraint(equalToConstant: 64),
            
            // Title below icon
            titleLabel.topAnchor.constraint(equalTo: appIconView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
        ])
        
        updateAppearance()
    }
    
    private func configureContent() {
        appIconView.image = windowInfo.appIcon
        
        // Use window title if available and different from app name, otherwise just app name
        let displayTitle: String
        if !windowInfo.title.isEmpty && windowInfo.title != windowInfo.ownerName {
            displayTitle = windowInfo.title
        } else {
            displayTitle = windowInfo.ownerName
        }
        titleLabel.stringValue = displayTitle
    }
    
    // MARK: - Appearance
    
    private func updateAppearance() {
        let accentColor = NSColor.controlAccentColor
        
        if isSelected {
            highlightBorderLayer.borderColor = accentColor.cgColor
            containerView.material = .selection
            
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.4
            layer?.shadowOffset = CGSize(width: 0, height: -2)
            layer?.shadowRadius = 10
        } else if isHovered {
            highlightBorderLayer.borderColor = accentColor.withAlphaComponent(0.6).cgColor
            containerView.material = .hudWindow
            
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.2
            layer?.shadowOffset = CGSize(width: 0, height: -1)
            layer?.shadowRadius = 5
        } else {
            highlightBorderLayer.borderColor = NSColor.clear.cgColor
            containerView.material = .hudWindow
            layer?.shadowOpacity = 0
        }
    }
    
    override func layout() {
        super.layout()
        highlightBorderLayer.frame = bounds
    }
    
    // MARK: - Mouse Tracking
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    override func mouseDown(with event: NSEvent) {
        isSelected = true
    }
    
    override func mouseUp(with event: NSEvent) {
        if isHovered {
            onSelect?(windowInfo)
        }
    }
}
