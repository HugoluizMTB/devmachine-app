import CoreGraphics
import Foundation

/// How many fixed-size cards a widget draws inside its frame, so it never
/// scrolls: the rest become a "+N more". A frame smaller than one card
/// shrinks the card to fit instead of showing nothing.
public struct CardGridFit: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let scale: Double

    public init(columns: Int, rows: Int, scale: Double) {
        self.columns = columns
        self.rows = rows
        self.scale = scale
    }

    public var capacity: Int { columns * rows }

    public func shown(of total: Int) -> Int { min(total, capacity) }
    public func hidden(of total: Int) -> Int { max(0, total - capacity) }

    public static func fit(in available: CGSize, card: CGSize, spacing: Double) -> CardGridFit {
        guard available.width > 0, available.height > 0, card.width > 0, card.height > 0 else {
            return CardGridFit(columns: 0, rows: 0, scale: 1)
        }
        let scale = min(1, available.width / card.width, available.height / card.height)
        let gap = spacing * scale
        return CardGridFit(
            columns: count(available.width, item: card.width * scale, gap: gap),
            rows: count(available.height, item: card.height * scale, gap: gap),
            scale: scale)
    }

    /// The small allowance keeps an exact fit from rounding down to one fewer.
    private static func count(_ length: Double, item: Double, gap: Double) -> Int {
        max(1, Int(((length + gap) / (item + gap) + 1e-9).rounded(.down)))
    }
}
