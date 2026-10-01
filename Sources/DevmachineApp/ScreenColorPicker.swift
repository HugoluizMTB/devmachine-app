import AppKit
import DevmachineCore

/// The system loupe that follows the pointer over every screen; a click copies
/// the color under it as hex, Esc cancels.
@MainActor
enum ScreenColorPicker {
    private static var sampler: NSColorSampler?

    static func pick(onCopy: @escaping @MainActor (String) -> Void) {
        guard sampler == nil else { return }
        let sampler = NSColorSampler()
        Self.sampler = sampler
        sampler.show { color in
            MainActor.assumeIsolated {
                Self.sampler = nil
                guard let color, let hex = hex(of: color) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)
                onCopy(hex)
            }
        }
    }

    static func hex(of color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return ScreenColor.hex(
            red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }
}
