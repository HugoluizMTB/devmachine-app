import Foundation

/// The sidebars' banner copy, in Core so its wording is tested once and
/// names the file the person has to open.
public enum StackBoardCopy {
    /// `keepsLastGood`: the file read well once, so the store still draws
    /// that layout rather than the default.
    public static func invalid(file: String, problem: BoardProblem, keepsLastGood: Bool = false) -> String {
        let place = problem.line.map { "\(file) has a problem at line \($0)" } ?? "\(file) has a problem"
        let shown = keepsLastGood ? "The last good layout" : "The default layout"
        return "\(place): \(problem.message). \(shown) shows until it is fixed; nothing is written meanwhile."
    }

    public static func saveFailed(file: String, error: String) -> String {
        "Could not save \(file): \(error)"
    }

    public static let resetHint =
        "The sidebar and the Context tab are lists of widgets. A reset brings back the default list of that area."

    public static func resetTitle(_ surface: String) -> String { "Reset \(displayName(surface))" }

    public static func resetConfirmation(_ surface: String) -> String {
        let file = StackArea.fileName(surface)
        return "The \(displayName(surface)) goes back to its default widgets. The current \(file) is kept as \(file).bak."
    }

    public static func resetFailed(_ surface: String) -> String { "Could not reset the \(displayName(surface))" }

    private static func displayName(_ surface: String) -> String {
        surface.replacingOccurrences(of: "-", with: " ")
    }
}
