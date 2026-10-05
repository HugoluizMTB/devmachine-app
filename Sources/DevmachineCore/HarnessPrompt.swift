import Foundation

/// A first message handed to a harness on its command line, so a new
/// session opens already answering it.
public enum HarnessPrompt {
    public static let operatorIntro = "Explain to me what I can do here."

    /// The harnesses known to take a first message as a positional argument
    /// (`claude '<prompt>'`, `codex '<prompt>'`).
    public static let positional: Set<HarnessID> = [.claude, .codex]

    /// The startup line asking `prompt`, or nil when the harness has no known
    /// way to take one; that harness then starts plain.
    public static func command(_ command: String, harness: HarnessID, prompt: String) -> String? {
        guard positional.contains(harness) else { return nil }
        return command + " " + shellQuoted(prompt)
    }

    public static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
