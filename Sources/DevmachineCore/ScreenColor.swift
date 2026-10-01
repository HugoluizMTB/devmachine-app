import Foundation

/// The text the color picker puts on the clipboard for a sampled sRGB color.
public enum ScreenColor {
    public static func hex(red: Double, green: Double, blue: Double) -> String {
        "#" + [red, green, blue].map { String(format: "%02X", byte($0)) }.joined()
    }

    private static func byte(_ component: Double) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }
}
