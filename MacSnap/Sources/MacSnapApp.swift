import AppKit

/// Main entry point for MacSnap
@main
struct MacSnapApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        
        // Ensure we don't appear in the dock
        app.setActivationPolicy(.accessory)
        
        app.run()
    }
}
