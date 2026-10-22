import SwiftUI

/// Corner radii of the app's own surfaces, from the smallest to the largest.
enum DMRadius {
    static let terminal: CGFloat = 4
    static let keyCap: CGFloat = 5
    static let row: CGFloat = 6
    static let control: CGFloat = 7
    static let tile: CGFloat = 8
    static let pill: CGFloat = 10
    static let toast: CGFloat = 12
    static let panel: CGFloat = 14
    static let card: CGFloat = 16
    static let bubble: CGFloat = 20
}

/// Sizes an icon button reserves for its click area, so a small glyph is
/// still easy to hit.
enum DMHitSize {
    static let compact = CGSize(width: 18, height: 18)
    static let regular = CGSize(width: 20, height: 20)
    static let header = CGSize(width: 20, height: 16)
    static let strip = CGSize(width: 22, height: 22)
    static let footer = CGSize(width: 24, height: 24)
}

/// The spacing scale, in points at 100%. Views read it scaled through
/// `@Environment(\.dmMetrics)`: `m.space.md`.
enum DMSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 24
}

/// How tall a labelled button or a field is, in points at 100%.
enum DMControlHeight {
    static let small: CGFloat = 22
    static let regular: CGFloat = 28
    static let large: CGFloat = 34
}

/// Glyph sizes, in points at 100%: the status dot of a row up to the symbol
/// over an empty or failed state.
enum DMIconSize {
    static let dot: CGFloat = 7
    static let xs: CGFloat = 9.5
    static let sm: CGFloat = 11
    static let md: CGFloat = 12.5
    static let lg: CGFloat = 20
    /// The glyph before a sidebar place (Workspaces, Chats, Schedule).
    static let navGlyph: CGFloat = 12
    /// The harness icon or terminal glyph before a session's name, and the
    /// height of the name line it sits on.
    static let sessionGlyph: CGFloat = 12
    static let sessionGlyphLine: CGFloat = 16
}

/// The inside of a list row and the gap around it, in points at 100%.
enum DMRowInset {
    static let horizontal: CGFloat = 10
    static let vertical: CGFloat = 7
    static let outer: CGFloat = 6
}

/// The padding of a `DMSection`, in points at 100%.
enum DMSectionInset {
    static let panel = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
    static let sidebarGroup = EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
    static let sidebarFooter = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
}

/// Widths of floating cards, sheets and palettes, in points at 100%.
enum DMCardWidth {
    static let toast: CGFloat = 220
    static let banner: CGFloat = 300
    static let sheetSmall: CGFloat = 360
    static let sheet: CGFloat = 420
    static let sheetLarge: CGFloat = 460
    static let sheetWide: CGFloat = 520
    static let palette: CGFloat = 600
    static let errorState: CGFloat = 440
}
