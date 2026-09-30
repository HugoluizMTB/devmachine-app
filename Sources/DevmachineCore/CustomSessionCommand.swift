import Foundation

/// A command typed by hand for one new session, run as the session's first
/// line the same way a coding harness starts.
public enum CustomSessionCommand {
    /// The line to run, or nil when there is nothing to run. Line breaks become
    /// spaces: the whole text is sent before a single Return.
    public static func normalized(_ raw: String) -> String? {
        let joined = raw.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = joined.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The short, most-recent-first list of commands offered as quick picks.
public enum RecentCommands {
    public static let capacity = 8

    public static func recording(_ command: String, in list: [String], capacity: Int = capacity) -> [String] {
        Array(([command] + list.filter { $0 != command }).prefix(capacity))
    }

    /// The lists in priority order, each command once, cut to `capacity`.
    public static func merged(_ lists: [[String]], capacity: Int = capacity) -> [String] {
        var seen = Set<String>()
        return Array(lists.joined().filter { seen.insert($0).inserted }.prefix(capacity))
    }
}
