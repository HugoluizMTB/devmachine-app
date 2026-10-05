import Foundation

public enum JobFailure {
    /// The CLI's own words for why it stopped: its last `error:` line.
    public static func cause(_ lines: [String]) -> String? {
        guard let line = lines.last(where: { $0.hasPrefix("error:") || $0.hasPrefix("Error:") }) else { return nil }
        let cause = line.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
        return cause.isEmpty ? nil : cause
    }
}
