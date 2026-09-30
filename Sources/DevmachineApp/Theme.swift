import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
    static let dmContentBgHex: UInt32 = 0x14191F
    static let dmSidebarBgHex: UInt32 = 0x0E1217
    static let dmContentBg = Color(hex: dmContentBgHex)   // center (required)
    static let dmSidebarBg = Color(hex: dmSidebarBgHex)   // sidebar, a bit darker
    static let dmRowText = Color(hex: 0xC9CED4)
    static let dmMuted = Color(hex: 0x767E88)
    static let dmSelection = Color.white.opacity(0.08)
    static let dmHover = Color.white.opacity(0.04)
    static let dmDivider = Color.white.opacity(0.06)
    static let dmStripe = Color.white.opacity(0.022)
    static let dmBand = Color.black.opacity(0.14)
    static let dmActive = Color.white.opacity(0.10)
    static let dmStroke = Color.white.opacity(0.12)
    static let dmSkeleton = Color.white.opacity(0.07)
}
