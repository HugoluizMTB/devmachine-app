import Foundation

/// The counts the CLI prints when a sync ends, `main: ok=41 changed=3 failed=0`.
public struct SyncSummary: Equatable, Sendable {
    public let ok: Int
    public let changed: Int
    public let failed: Int

    public init(ok: Int, changed: Int, failed: Int) {
        self.ok = ok
        self.changed = changed
        self.failed = failed
    }

    public static func parse(_ lines: [String]) -> SyncSummary? {
        for line in lines.reversed() {
            if let summary = parseLine(LogText.plain(line)) { return summary }
        }
        return nil
    }

    private static func parseLine(_ line: String) -> SyncSummary? {
        var values: [String: Int] = [:]
        for token in line.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Int(parts[1]) else { continue }
            values[String(parts[0])] = value
        }
        guard let ok = values["ok"], let changed = values["changed"], let failed = values["failed"] else { return nil }
        return SyncSummary(ok: ok, changed: changed, failed: failed)
    }
}
