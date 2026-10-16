import Foundation

/// The app always uses the thin scroll bar that shows only while scrolling,
/// whatever System Settings says: the sidebars and panels are narrow, and the
/// "Always" setting's track takes their width.
enum ScrollBarStyle {
    static let key = "AppleShowScrollBars"
    static let value = "WhenScrolling"
    /// Demo only: stands in for System Settings' choice, so a render can show
    /// that the app's own value wins over it.
    static let simulatedSettingKey = "DEVMACHINE_DEMO_SCROLL_BARS"

    /// Runs before any window exists. AppKit reads the key from the argument
    /// domain, which ranks above the system's own, at launch and again after
    /// every system change, so the value keeps winning.
    static func apply(
        to defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        if let simulated = environment[simulatedSettingKey] {
            defaults.register(defaults: [key: simulated])
        }
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[key] = value
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}
