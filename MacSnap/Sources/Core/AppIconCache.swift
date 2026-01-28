import AppKit

/// Thread-safe cache for application icons.
/// Avoids repeated icon lookups for the same process during picker display.
final class AppIconCache {
    
    static let shared = AppIconCache()
    
    private var cache: [pid_t: NSImage] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    /// Get the icon for a process, using cache if available
    /// - Parameter pid: The process identifier
    /// - Returns: The app icon, or nil if not found
    func icon(for pid: pid_t) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cache[pid] {
            return cached
        }
        
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else {
            return nil
        }
        
        cache[pid] = icon
        return icon
    }
    
    /// Clear the cache (call when picker is dismissed)
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}
