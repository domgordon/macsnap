import AppKit
import ApplicationServices

/// Caches CGWindowListCopyWindowInfo results to avoid expensive repeated syscalls.
/// The window list is fetched at most once per operation (within maxAge).
final class WindowListCache {
    
    static let shared = WindowListCache()
    
    // MARK: - Properties
    
    private var cache: [[String: Any]]?
    private var cacheTime: Date?
    
    /// Default max age for cache validity (100ms)
    private let defaultMaxAge: TimeInterval = 0.1
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get the current window list, using cache if fresh enough
    /// - Parameter maxAge: Maximum age of cached data to accept (default 100ms)
    /// - Returns: Array of window info dictionaries
    func getWindowList(maxAge: TimeInterval? = nil) -> [[String: Any]] {
        let effectiveMaxAge = maxAge ?? defaultMaxAge
        
        // Return cached data if fresh
        if let cache = cache, let time = cacheTime,
           Date().timeIntervalSince(time) < effectiveMaxAge {
            return cache
        }
        
        // Fetch fresh data
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let freshData = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        
        cache = freshData
        cacheTime = Date()
        
        return freshData
    }
    
    /// Invalidate the cache, forcing a fresh fetch on next access
    func invalidate() {
        cache = nil
        cacheTime = nil
    }
    
    // MARK: - Window Validation
    
    /// Check if a window info dictionary represents a valid standard window
    /// - Parameters:
    ///   - windowInfo: Window info dictionary from CGWindowListCopyWindowInfo
    ///   - excludePID: Optional PID to exclude (e.g., the frontmost app)
    ///   - minSize: Minimum size for valid windows (default 100x100)
    /// - Returns: true if this is a valid standard window
    static func isValidWindow(
        _ windowInfo: [String: Any],
        excludePID: pid_t? = nil,
        minSize: CGFloat = 100
    ) -> Bool {
        guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
              let layer = windowInfo[kCGWindowLayer as String] as? Int,
              let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
            return false
        }
        
        // Skip excluded app
        if let excludePID = excludePID, ownerPID == excludePID {
            return false
        }
        
        // Skip non-normal windows (layer 0 = normal windows)
        if layer != 0 {
            return false
        }
        
        // Skip MacSnap's picker window (layer check already excludes it, but be explicit)
        // Allow other MacSnap windows like onboarding to appear in the picker
        // The picker window has a high window level so it's filtered by layer != 0 above
        
        // Skip small windows (tooltips, etc.)
        let width = boundsDict["Width"] ?? 0
        let height = boundsDict["Height"] ?? 0
        if width < minSize || height < minSize {
            return false
        }
        
        return true
    }
    
    /// Extract window frame from window info dictionary
    /// - Parameter windowInfo: Window info dictionary from CGWindowListCopyWindowInfo
    /// - Returns: Frame in NSScreen coordinates, or nil if invalid
    static func getFrame(_ windowInfo: [String: Any]) -> CGRect? {
        guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
            return nil
        }
        return CoordinateConverter.cgBoundsToNS(boundsDict)
    }
    
    /// Get the window ID from window info
    static func getWindowID(_ windowInfo: [String: Any]) -> CGWindowID? {
        windowInfo[kCGWindowNumber as String] as? CGWindowID
    }
    
    /// Get the owner PID from window info
    static func getOwnerPID(_ windowInfo: [String: Any]) -> pid_t? {
        windowInfo[kCGWindowOwnerPID as String] as? pid_t
    }
    
    /// Get the owner name from window info
    static func getOwnerName(_ windowInfo: [String: Any]) -> String? {
        windowInfo[kCGWindowOwnerName as String] as? String
    }
    
    /// Get the window title from window info (often empty or generic)
    static func getTitle(_ windowInfo: [String: Any]) -> String? {
        windowInfo[kCGWindowName as String] as? String
    }
}
