import CoreGraphics
import Foundation

/// How far content must move down so a button floating over it covers
/// none of it: the button that reopens a collapsed sidebar sits over the
/// top-left corner of whatever is in the centre.
public enum FloatingButtonClearance {
    /// Zero when there is no button, when the content starts right of it,
    /// or when it already starts below it. All values in the same
    /// coordinates and already scaled to the text size.
    public static func topInset(button: CGRect?, contentMinX: Double, contentMinY: Double, gap: Double) -> Double {
        guard let button, contentMinX < button.maxX + gap else { return 0 }
        return max(0, button.maxY + gap - contentMinY)
    }
}
