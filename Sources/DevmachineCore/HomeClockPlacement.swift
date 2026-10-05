import Foundation

/// Whether Home's clock can sit in the middle of all of Home instead of in
/// the middle of the column beside the cards: only when it then still
/// clears the cards column by `gap`.
public enum HomeClockPlacement {
    public static func centresInHome(homeWidth: Double, cardsMaxX: Double, clockWidth: Double, gap: Double) -> Bool {
        homeWidth / 2 - clockWidth / 2 >= cardsMaxX + gap
    }
}
