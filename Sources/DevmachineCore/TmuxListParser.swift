import Foundation

public enum TmuxListParser {
    static let paneSentinel = RemoteCommands.paneSentinel
    static let processSentinel = RemoteCommands.processSentinel

    /// Reads `RemoteCommands.listSessions`: session lines, then sections
    /// opened by the pane and process sentinels in either order. A pane line
    /// is `session|command` or `session|command|pid`; with a pid and a
    /// process table, every program under the pane counts, not only the one
    /// in front. Programs match by exact name, so a bare `node` is nothing.
    public static func parse(
        _ output: String,
        processNames: [HarnessID: Set<String>]
    ) -> [TmuxSession] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.contains(paneSentinel) else {
            return sessionsOnly(Array(lines.prefix { $0 != processSentinel }))
        }
        var sessionLines: [String] = []
        var paneLines: [String] = []
        var processLines: [String] = []
        var section: String?
        for line in lines {
            if line == paneSentinel || line == processSentinel {
                section = line
                continue
            }
            switch section {
            case nil: sessionLines.append(line)
            case paneSentinel: paneLines.append(line)
            default: processLines.append(line)
            }
        }

        var harnessesByProgram: [String: Set<HarnessID>] = [:]
        for (harness, programs) in processNames {
            for program in programs {
                harnessesByProgram[program, default: []].insert(harness)
            }
        }

        let panes = paneLines.compactMap(Pane.init)
        let entries = ProcessTree.parse(processLines.joined(separator: "\n"))
        let programsUnderPane = entries.isEmpty ? [:] : ProcessTree.matchingPrograms(
            Set(harnessesByProgram.keys), roots: panes.compactMap(\.pid), in: entries)

        var harnessesBySession: [String: Set<HarnessID>] = [:]
        for pane in panes {
            let programs = [pane.command] + (pane.pid.flatMap { programsUnderPane[$0] } ?? [])
            for program in programs {
                harnessesBySession[pane.session, default: []].formUnion(harnessesByProgram[program] ?? [])
            }
        }

        return sessionLines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let windows = Int(parts[1]) else { return nil }
            return TmuxSession(
                name: parts[0], windows: windows,
                harnesses: harnessesBySession[parts[0]] ?? [])
        }
    }

    private struct Pane {
        let session: String
        let command: String
        let pid: Int?

        init?(_ line: String) {
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            session = parts[0]
            if let bar = parts[1].lastIndex(of: "|"), let pid = Int(parts[1][parts[1].index(after: bar)...]) {
                command = String(parts[1][..<bar])
                self.pid = pid
            } else {
                command = parts[1]
                pid = nil
            }
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
