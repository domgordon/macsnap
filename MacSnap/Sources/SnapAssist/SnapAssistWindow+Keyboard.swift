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
        
        // Uses Layout constants from SnapAssistWindow for consistent calculations
        let availableWidth = firstZone.bounds.width - Layout.totalPaddingBothSides
        let thumbnailWidth = WindowThumbnailView.totalSize.width
        let columns = max(1, Int((availableWidth + Layout.thumbnailSpacing) / (thumbnailWidth + Layout.thumbnailSpacing)))
        
        let newIndex = selectedIndex + (rowDelta * columns)
        if newIndex >= 0 && newIndex < windows.count {
            selectedIndex = newIndex
            updateSelection()
        }
    }
}
