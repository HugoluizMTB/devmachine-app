import Foundation

/// The sidebars' banner copy, in Core so its wording is tested once and
/// names the file the person has to open.
public enum StackBoardCopy {
    public static func invalid(file: String, problem: BoardProblem) -> String {
        "\(file) has a problem at \(problem). The default layout shows until it is fixed; nothing is written meanwhile."
    }

    public static func saveFailed(file: String, error: String) -> String {
        "Could not save \(file): \(error)"
    }
}
