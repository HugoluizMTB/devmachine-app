import SwiftUI

/// Every size in the app's own interface goes through here, so one setting
/// scales all of them. A view that asked for 11 points still asks for 11; what
/// changes is what 11 means.
enum DMFont {
    /// Read at render time. The tree is rebuilt when the setting changes, which
    /// is what makes a new value reach sizes already laid out.
    nonisolated(unsafe) static var scale: Double = 1

    static func size(_ base: CGFloat) -> CGFloat {
        let scaled = base * CGFloat(scale)
        return max(1, (scaled * 2).rounded() / 2)
    }
}

extension Font {
    static func dm(
        _ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default
    ) -> Font {
        .system(size: DMFont.size(size), weight: weight, design: design)
    }
}
