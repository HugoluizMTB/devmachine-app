import Foundation

public enum HomeBoardCopy {
    public static let invalidTitle = "home.yml has a problem"
    public static let invalidNote = "Home keeps the last good layout and saves nothing until the file is fixed."
    public static let resetHint = "Puts the clock, summary, machines and usage widgets back where they started. "
        + "The current layout is kept beside it as home.yml.bak."
    public static let resetConfirmation = "Home goes back to its first layout. The current file is saved as home.yml.bak."

    public static func placementsSaveFailed(_ error: String) -> String {
        "Couldn't save which widgets were placed: \(error)"
    }

    public static func invalidCause(_ problem: BoardProblem) -> String {
        let sentence = problem.message.hasSuffix(".") ? problem.message : problem.message + "."
        return problem.line.map { "Line \($0): \(sentence)" } ?? sentence
    }
}
