import Foundation

public struct TmuxSession: Equatable, Identifiable, Sendable {
    public let name: String
    public let windows: Int
    public let harnesses: Set<HarnessID>
    public var id: String { name }

    public init(name: String, windows: Int, harnesses: Set<HarnessID>) {
        self.name = name
        self.windows = windows
        self.harnesses = harnesses
    }
}


public enum SessionName {
    /// tmux treats a name with a space or a dot as something to quote or split,
    /// so the app keeps names to letters, digits, dash and underscore.
    public static func isValid(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// What to show while the field holds something the rule rejects.
    public static func hint(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return isValid(trimmed) ? nil : "Letters, numbers, - and _ only"
    }

    /// The same name with the rejected characters turned into dashes, for a
    /// one-click fix rather than retyping.
    public static func suggestion(for raw: String) -> String {
        let mapped = raw.trimmingCharacters(in: .whitespaces).map { ch -> Character in
            (ch.isLetter && ch.isASCII) || ch.isNumber || ch == "-" || ch == "_" ? ch : "-"
        }
        var name = String(mapped)
        while name.hasPrefix("-") { name.removeFirst() }
        while name.hasSuffix("-") { name.removeLast() }
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        return name
    }

    /// A quick session is named after its folder plus a short discriminator.
    /// Multiplexers require the name before creation, so the app supplies it.
    public static func automatic(directory: String, suffix: String) -> String {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = URL(fileURLWithPath: trimmed).lastPathComponent
        let base = suggestion(for: folder)
        let safeSuffix = suggestion(for: suffix.lowercased())
        return "\(base.isEmpty ? "session" : base)-\(safeSuffix.isEmpty ? "xx" : safeSuffix)"
    }
}
