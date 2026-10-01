import AppKit
import DevmachineCore

/// The system loupe that follows the pointer over every screen; a click copies
/// the color under it as hex, Esc cancels.
@MainActor
enum ScreenColorPicker {
    static func pick(onCopy: @escaping @MainActor (String) -> Void) {
        NSColorSampler().show { color in
            MainActor.assumeIsolated {
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
