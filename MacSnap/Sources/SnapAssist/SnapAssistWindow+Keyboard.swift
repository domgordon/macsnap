import AppKit

// MARK: - Keyboard Navigation

extension SnapAssistWindow {
    
    /// Handle keyboard input for navigation and selection
    func handleKeyDown(_ event: NSEvent) {
        guard !windows.isEmpty else {
            dismissPicker()
            return
        }
        
        switch event.keyCode {
        case KeyCodes.escape:
            dismissPicker()
            
        case KeyCodes.returnKey, KeyCodes.enter:
            if selectedIndex < windows.count {
                let selected = windows[selectedIndex]
                debugLog("SnapAssistWindow: Enter pressed, selectedIndex=\(selectedIndex), window='\(selected.title)' at \(selected.frame)")
                selectWindow(selected)
            }
            
        case KeyCodes.leftArrow:
            moveSelection(by: -1)
            
        case KeyCodes.rightArrow:
            moveSelection(by: 1)
            
        case KeyCodes.downArrow:
            moveSelectionVertical(by: 1)
            
        case KeyCodes.upArrow:
            moveSelectionVertical(by: -1)
            
        case KeyCodes.tab:
            moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            
        default:
            break
        }
    }
    
    /// Move selection by delta (horizontal navigation)
    func moveSelection(by delta: Int) {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + windows.count) % windows.count
        updateSelection()
    }
    
    /// Move selection by row delta (vertical navigation)
    func moveSelectionVertical(by rowDelta: Int) {
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
}

// MARK: - Key Codes

/// Centralized key code constants for keyboard handling
private enum KeyCodes {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    static let tab: UInt16 = 48
}
