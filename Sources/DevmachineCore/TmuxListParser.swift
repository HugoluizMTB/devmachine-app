import Foundation

public enum TmuxListParser {
    static let paneSentinel = RemoteCommands.paneSentinel

    public static func parse(_ output: String) -> [TmuxSession] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let cut = lines.firstIndex(of: paneSentinel) else {
            return sessionsOnly(Array(lines))
        }
        let sessionLines = Array(lines[..<cut])
        let paneLines = Array(lines[(cut + 1)...])

        var claudeBySession: [String: Bool] = [:]
        for pane in paneLines {
            let parts = pane.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[1] == "claude" { claudeBySession[parts[0]] = true }
        }

        return sessionLines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let windows = Int(parts[1]) else { return nil }
            return TmuxSession(name: parts[0], windows: windows, hasClaude: claudeBySession[parts[0]] ?? false)
        }
    }

    private static func sessionsOnly(_ lines: [String]) -> [TmuxSession] {
        lines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let windows = Int(parts[1]) else { return nil }
            return TmuxSession(name: parts[0], windows: windows, hasClaude: false)
        }
    }
}
