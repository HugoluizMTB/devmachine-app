import Foundation

public enum TmuxListParser {
    static let paneSentinel = RemoteCommands.paneSentinel

    public static func parse(
        _ output: String,
        processNames: [HarnessID: Set<String>]
    ) -> [TmuxSession] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let cut = lines.firstIndex(of: paneSentinel) else {
            return sessionsOnly(Array(lines))
        }
        let sessionLines = Array(lines[..<cut])
        let paneLines = Array(lines[(cut + 1)...])

        var harnessesByProgram: [String: Set<HarnessID>] = [:]
        for (harness, programs) in processNames {
            for program in programs {
                harnessesByProgram[program, default: []].insert(harness)
            }
        }

        var harnessesBySession: [String: Set<HarnessID>] = [:]
        for pane in paneLines {
            let parts = pane.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            harnessesBySession[parts[0], default: []].formUnion(
                harnessesByProgram[parts[1]] ?? [])
        }

        return sessionLines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let windows = Int(parts[1]) else { return nil }
            return TmuxSession(
                name: parts[0], windows: windows,
                harnesses: harnessesBySession[parts[0]] ?? [])
        }
    }

    private static func sessionsOnly(_ lines: [String]) -> [TmuxSession] {
        lines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let windows = Int(parts[1]) else { return nil }
            return TmuxSession(name: parts[0], windows: windows, harnesses: [])
        }
    }
}
