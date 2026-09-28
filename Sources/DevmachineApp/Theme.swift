import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
    static let dmContentBg = Color(hex: 0x14191F)   // center (required)
    static let dmSidebarBg = Color(hex: 0x0E1217)   // sidebar, a bit darker
    static let dmRowText = Color(hex: 0xC9CED4)
    static let dmMuted = Color(hex: 0x767E88)
    static let dmSelection = Color.white.opacity(0.08)
    static let dmHover = Color.white.opacity(0.04)
    static let dmDivider = Color.white.opacity(0.06)
    static let dmActive = Color.white.opacity(0.10)
    static let dmFill = Color.white.opacity(0.08)
    static let dmStroke = Color.white.opacity(0.12)
}

extension Color {
    /// A stable colour for a name, so every tracker/site gets its own without a
    /// hard-coded list. Same name, same hue, on every launch.
    static func dmTag(_ name: String) -> Color {
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.45, brightness: 0.85)
    }
}
