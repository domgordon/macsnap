import AppKit
import ApplicationServices

/// Centralized window discovery utilities.
/// Extracts window lookup logic from WindowManager for better separation of concerns.
enum WindowDiscovery {
    
    // MARK: - Frontmost Window
    
    /// Get the frontmost window of the frontmost application
    static func getFrontmostWindow() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        // Try focused window first
        if let focusedWindow: AXUIElement = AXHelpers.getFocusedWindow(appElement) {
            return focusedWindow
        }
        
        // Fallback to first window
        if let windows = AXHelpers.getWindows(appElement), let firstWindow = windows.first {
            return firstWindow
        }
        
        return nil
    }
    
    /// Result containing frontmost window details (avoids redundant AX calls)
    struct FrontmostWindowDetails {
        let window: AXUIElement
        let windowID: CGWindowID?
        let frame: CGRect  // In NSScreen coordinates
    }
    
    /// Get the frontmost window with its ID and frame in a single operation
    /// Avoids redundant AX calls by fetching all details at once
    static func getFrontmostWindowWithDetails() -> FrontmostWindowDetails? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        guard let window = getFrontmostWindow(),
              let axFrame = AXHelpers.getFrame(window) else {
            return nil
        }
        
        let nsFrame = CoordinateConverter.axToNS(axFrame)
        
        // Find matching window ID in CG window list
        let windowID = findWindowID(forAXFrame: axFrame, ownerPID: frontApp.processIdentifier)
        
        return FrontmostWindowDetails(window: window, windowID: windowID, frame: nsFrame)
    }
    
    /// Get the CGWindowID of the frontmost window by matching its AX frame against the window list
    static func getFrontmostWindowID() -> CGWindowID? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let window = getFrontmostWindow(),
              let axFrame = AXHelpers.getFrame(window) else {
            return nil
        }
        
        return findWindowID(forAXFrame: axFrame, ownerPID: frontApp.processIdentifier)
    }
    
    // MARK: - Window ID Lookup
    
    /// Find the CGWindowID for an AX window frame
    private static func findWindowID(forAXFrame axFrame: CGRect, ownerPID: pid_t) -> CGWindowID? {
        let windowList = WindowListCache.shared.getWindowList()
        
        for windowInfo in windowList {
            guard let pid = WindowListCache.getOwnerPID(windowInfo),
                  pid == ownerPID,
                  let windowID = WindowListCache.getWindowID(windowInfo),
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let cgFrame = CoordinateConverter.cgRect(from: boundsDict) else {
                continue
            }
            
            if FrameMatcher.matchesExact(axFrame, cgFrame) {
                debugLog("WindowDiscovery: Found window ID: \(windowID)")
                return windowID
            }
        }
        
        debugLog("WindowDiscovery: Could not find window ID")
        return nil
    }
    
    // MARK: - Window Enumeration
    
    /// Get all visible windows on a screen, excluding specified window and clean-snapped windows
    /// - Parameters:
    ///   - excludeWindowID: Window ID to exclude (e.g., the window that was just snapped)
    ///   - screen: The screen to get windows for
    /// - Returns: Array of WindowInfo for eligible windows
    static func getVisibleWindows(on screen: NSScreen, excluding excludeWindowID: CGWindowID?) -> [WindowInfo] {
        let windowList = WindowListCache.shared.getWindowList()
        
        // Intermediate structure for candidate windows
        struct Candidate {
            let windowID: CGWindowID
            let ownerPID: pid_t
            let ownerName: String
            let cgTitle: String
            let cgFrame: CGRect
            let nsFrame: CGRect
        }
        
        var candidates: [Candidate] = []
        
        // First pass: collect valid window candidates
        for (currentIndex, windowInfo) in windowList.enumerated() {
            guard WindowListCache.isValidWindow(windowInfo, excludePID: nil, minSize: 100),
                  let windowID = WindowListCache.getWindowID(windowInfo),
                  let ownerPID = WindowListCache.getOwnerPID(windowInfo),
                  let ownerName = WindowListCache.getOwnerName(windowInfo),
                  let nsFrame = WindowListCache.getFrame(windowInfo),
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let cgFrame = CoordinateConverter.cgRect(from: boundsDict) else {
                continue
            }
            
            // Skip excluded window
            if let excludeID = excludeWindowID, windowID == excludeID {
                continue
            }
            
            // Check if window is on the specified screen
            let windowCenter = CGPoint(x: nsFrame.midX, y: nsFrame.midY)
            if !screen.frame.contains(windowCenter) {
                continue
            }
            
            // Skip clean-snapped windows that aren't overlapped
            if FrameMatcher.detectSnapPosition(for: nsFrame, on: screen) != nil {
                let isOverlapped = windowList[0..<currentIndex].contains { higherWindowInfo in
                    guard WindowListCache.isValidWindow(higherWindowInfo, excludePID: nil, minSize: 100),
                          let higherFrame = WindowListCache.getFrame(higherWindowInfo) else {
                        return false
                    }
                    return higherFrame.intersects(nsFrame)
                }
                
                if !isOverlapped {
                    debugLog("WindowDiscovery: Skipping clean-snapped '\(ownerName)' at \(nsFrame)")
                    continue
                }
                debugLog("WindowDiscovery: Including overlapped snap-positioned '\(ownerName)'")
            }
            
            candidates.append(Candidate(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                cgTitle: WindowListCache.getTitle(windowInfo) ?? ownerName,
                cgFrame: cgFrame,
                nsFrame: nsFrame
            ))
        }
        
        // Second pass: identify apps with multiple windows
        var windowCountByPID: [pid_t: Int] = [:]
        for candidate in candidates {
            windowCountByPID[candidate.ownerPID, default: 0] += 1
        }
        let multiWindowPIDs = Set(windowCountByPID.filter { $0.value > 1 }.keys)
        
        // Third pass: build final WindowInfo array
        var windows: [WindowInfo] = []
        for candidate in candidates {
            let title: String
            
            if multiWindowPIDs.contains(candidate.ownerPID) {
                // Fetch real title via Accessibility API for disambiguation
                title = getRealWindowTitle(forFrame: candidate.cgFrame, ownerPID: candidate.ownerPID)
                    ?? candidate.cgTitle
            } else {
                title = candidate.cgTitle
            }
            
            debugLog("WindowDiscovery: Window \(candidate.windowID) '\(title)' at \(candidate.nsFrame)")
            
            // App icon is now lazily loaded via AppIconCache
            windows.append(WindowInfo(
                windowID: candidate.windowID,
                ownerPID: candidate.ownerPID,
                ownerName: candidate.ownerName,
                title: title,
                frame: candidate.nsFrame
            ))
        }
        
        debugLog("WindowDiscovery: Found \(windows.count) windows (\(multiWindowPIDs.count) apps with multiple)")
        return windows
    }
    
    // MARK: - Window Title Lookup
    
    /// Get the real window title by matching frame to an AXUIElement
    static func getRealWindowTitle(forFrame cgFrame: CGRect, ownerPID: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(ownerPID)
        
        guard let windows = AXHelpers.getWindows(appElement) else {
            return nil
        }
        
        for axWindow in windows {
            guard let axFrame = AXHelpers.getFrame(axWindow) else {
                continue
            }
            
            if FrameMatcher.matchesExact(axFrame, cgFrame) {
                return AXHelpers.getTitle(axWindow)
            }
        }
        
        return nil
    }
    
    // MARK: - Window Lookup by Frame
    
    /// Find an AX window element by matching its frame
    /// - Parameters:
    ///   - storedFrame: The frame to match (in NSScreen coordinates)
    ///   - ownerPID: The process ID that owns the window
    /// - Returns: The matching AXUIElement if found
    static func findWindow(withFrame storedFrame: CGRect, ownerPID: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(ownerPID)
        
        guard let windows = AXHelpers.getWindows(appElement) else {
            return nil
        }
        
        let storedAXFrame = CoordinateConverter.nsToAX(storedFrame)
        
        for axWindow in windows {
            guard let axFrame = AXHelpers.getFrame(axWindow) else {
                continue
            }
            
            if FrameMatcher.matchesExact(axFrame, storedAXFrame) {
                return axWindow
            }
        }
        
        return nil
    }
}
