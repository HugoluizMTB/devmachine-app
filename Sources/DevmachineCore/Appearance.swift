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

    /// Two layers paint a translucent pane: the terminal, so every cell is
    /// written and nothing stale can show through, and the container behind it,
    /// so the padding ring matches. Painted one over the other their alphas
    /// combine, so each gets the value that adds up to the one asked for.
    public static func layerOpacity(forCombined opacity: Double) -> Double {
        let wanted = clampTerminalOpacity(opacity)
        return 1 - (1 - wanted).squareRoot()
    }

    public static func clampTerminalOpacity(_ value: Double) -> Double {
        clamp(value, to: terminalOpacityRange, fallback: defaultTerminalOpacity)
    }

    public static func clampTerminalFontSize(_ value: Double) -> Double {
        clamp(value, to: terminalFontSizeRange, fallback: defaultTerminalFontSize)
    }

    /// How many terminals stay connected while you are not looking at them.
    public static let defaultKeptTerminals = 24
    public static let keptTerminalsRange = 4...64

    /// The same limits as a range of doubles, for a slider.
    public static let keptTerminalsSliderRange =
        Double(keptTerminalsRange.lowerBound)...Double(keptTerminalsRange.upperBound)

    public static func clampKeptTerminals(_ value: Int) -> Int {
        min(max(value, keptTerminalsRange.lowerBound), keptTerminalsRange.upperBound)
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
