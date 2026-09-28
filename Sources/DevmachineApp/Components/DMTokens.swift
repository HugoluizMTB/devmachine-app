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
