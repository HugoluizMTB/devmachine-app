import CoreGraphics

/// The main window's size the first time it opens. Without one, SwiftUI
/// sizes the window to its first content — the setup page — and the app
/// then opened barely larger than Settings, on every later launch too.
public enum MainWindowSizing {
    public static let minimum = CGSize(width: 900, height: 560)
    public static let screenFraction: CGFloat = 0.8

    /// 80% of the screen's visible frame, never below `minimum` and never
    /// larger than the screen itself, centered.
    public static func defaultFrame(visible: CGRect) -> CGRect {
        let width = min(max((visible.width * screenFraction).rounded(), minimum.width), visible.width)
        let height = min(max((visible.height * screenFraction).rounded(), minimum.height), visible.height)
        return CGRect(
            x: (visible.midX - width / 2).rounded(), y: (visible.midY - height / 2).rounded(),
            width: width, height: height)
    }

    /// The frame to apply at launch, or nil to keep the one AppKit restored.
    /// `savedFrame` is AppKit's own `NSWindow Frame <name>` default, read
    /// before any window exists: a frame the person saved always wins.
    public static func initialFrame(savedFrame: String?, visible: CGRect) -> CGRect? {
        guard savedFrame?.isEmpty ?? true else { return nil }
        return defaultFrame(visible: visible)
    }
}
