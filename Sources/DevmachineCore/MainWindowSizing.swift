import CoreGraphics

/// The main window's size the first time it opens. Without one, SwiftUI
/// sizes the window to its first content — the setup page — and the app
/// then opened barely larger than Settings, on every later launch too.
public enum MainWindowSizing {
    public static let minimum = CGSize(width: 900, height: 560)
    /// Room for the sidebar and Home's default board side by side.
    public static let preferred = CGSize(width: 1280, height: 800)
    public static let screenFraction: CGFloat = 0.8

    /// 80% of the screen's visible frame, at least `preferred` and
    /// `minimum`, but never larger than the screen itself, centered.
    public static func defaultFrame(visible: CGRect) -> CGRect {
        func fitted(_ side: CGFloat, preferred: CGFloat, minimum: CGFloat) -> CGFloat {
            min(max((side * screenFraction).rounded(), preferred, minimum), side)
        }
        let width = fitted(visible.width, preferred: preferred.width, minimum: minimum.width)
        let height = fitted(visible.height, preferred: preferred.height, minimum: minimum.height)
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
