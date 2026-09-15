import Foundation

/// The limits behind the appearance sliders. They live here, next to the
/// settings they bound, so the view and the stored value cannot disagree.
public enum Appearance {
    public static let defaultTerminalOpacity = 0.66
    public static let terminalOpacityRange = 0.2...1.0

    public static let defaultTerminalFontSize = 13.0
    public static let terminalFontSizeRange = 9.0...24.0

    public static let defaultUIFontScale = 1.0
    public static let uiFontScaleRange = 0.8...1.6

    public static func clampTerminalOpacity(_ value: Double) -> Double {
        clamp(value, to: terminalOpacityRange, fallback: defaultTerminalOpacity)
    }

    public static func clampTerminalFontSize(_ value: Double) -> Double {
        clamp(value, to: terminalFontSizeRange, fallback: defaultTerminalFontSize)
    }

    public static func clampUIFontScale(_ value: Double) -> Double {
        clamp(value, to: uiFontScaleRange, fallback: defaultUIFontScale)
    }

    /// A value outside the range is pulled to the nearest end; one that is not a
    /// number at all falls back, so a corrupt settings file cannot make the
    /// interface unreadable.
    private static func clamp(
        _ value: Double, to range: ClosedRange<Double>, fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
