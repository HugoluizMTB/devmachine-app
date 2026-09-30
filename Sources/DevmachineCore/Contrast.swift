import Foundation

/// WCAG 2 contrast between two sRGB colours given as 0xRRGGBB.
public enum Contrast {
    public static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (lighter, darker) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func luminance(_ hex: UInt32) -> Double {
        let (r, g, b) = channels(hex)
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// The colour a translucent white fill paints over an opaque background.
    public static func white(opacity: Double, over background: UInt32) -> UInt32 {
        let (r, g, b) = channels(background)
        func blend(_ channel: Double) -> UInt32 { UInt32((channel + (255 - channel) * opacity).rounded()) }
        return blend(r) << 16 | blend(g) << 8 | blend(b)
    }

    private static func channels(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
    }

    private static func linear(_ channel: Double) -> Double {
        let c = channel / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}
