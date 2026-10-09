import Foundation

public enum GitHead {
    public static func abbrevRefArguments(_ directory: String) -> [String] {
        ["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"]
    }

    public static func shortSHAArguments(_ directory: String) -> [String] {
        ["-C", directory, "rev-parse", "--short", "HEAD"]
    }

    /// nil for empty output; "HEAD" means detached, so the caller asks for the sha.
    public static func branch(fromAbbrevRef output: String) -> String? {
        let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
