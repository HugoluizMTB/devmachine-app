import Foundation

/// A transcript file found on disk, with the data the engine needs to pick
/// which ones to read (newest first, dropped once stale).
public struct ContextTranscriptFile: Equatable, Sendable {
    public let path: URL
    public let modified: Date
    /// The session inside `path` when one file holds many (opencode's
    /// database); nil when the file is the session.
    public let session: String?

    public init(path: URL, modified: Date, session: String? = nil) {
        self.path = path
        self.modified = modified
        self.session = session
    }
}

public enum ContextTranscriptDiscovery {
    /// The project's transcripts under one root directory, newest first,
    /// falling back to the single newest file when nothing was touched in
    /// the last `maxAgeHours` — mirrors `devmachine-infer.recent_transcripts`.
    public static func recent(
        in directories: [URL], glob: String, limit: Int = 4, maxAgeHours: Double = 12,
        fileManager: FileManager = .default
    ) -> [ContextTranscriptFile] {
        var files: [ContextTranscriptFile] = []
        for dir in directories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for url in entries where matchesGlob(url.lastPathComponent, glob) {
                guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate else { continue }
                files.append(ContextTranscriptFile(path: url, modified: mtime))
            }
        }
        files.sort { $0.modified > $1.modified }
        let floor = Date().addingTimeInterval(-maxAgeHours * 3600)
        let fresh = files.filter { $0.modified >= floor }
        let chosen = fresh.isEmpty ? Array(files.prefix(1)) : fresh
        return Array(chosen.prefix(limit))
    }

    /// A `prefix*suffix` glob match (at most one `*`) — the only shape this
    /// module's patterns use (`*.jsonl`, `rollout-*.jsonl`, `<id>*.jsonl`).
    static func matchesGlob(_ name: String, _ pattern: String) -> Bool {
        guard let starIndex = pattern.firstIndex(of: "*") else { return name == pattern }
        let prefix = String(pattern[pattern.startIndex..<starIndex])
        let suffix = String(pattern[pattern.index(after: starIndex)...])
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        return name.count >= prefix.count + suffix.count
    }
}
