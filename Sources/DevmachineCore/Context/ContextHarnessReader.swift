import Foundation

/// One coding harness's sessions on this machine: which belong to a project
/// and what one of them holds. The engine knows a harness only through this,
/// so each reader loads its own storage (JSONL, JSON, SQLite) its own way.
public protocol ContextHarnessReader: Sendable {
    var harness: HarnessID { get }
    /// The project's sessions, newest first, at most `limit`.
    func recentTranscripts(for project: URL, limit: Int, fileManager: FileManager) -> [ContextTranscriptFile]
    /// One session, read into what the shared extraction runs over.
    func pass(for transcript: ContextTranscriptFile) -> ContextHarnessPass
}

/// A harness that keeps one JSONL file per session.
struct JSONLHarnessReader: ContextHarnessReader {
    let harness: HarnessID
    let discover: @Sendable (URL, Int, FileManager) -> [ContextTranscriptFile]
    let extract: @Sendable ([[String: Any]]) -> ContextHarnessPass

    func recentTranscripts(for project: URL, limit: Int, fileManager: FileManager) -> [ContextTranscriptFile] {
        discover(project, limit, fileManager)
    }

    func pass(for transcript: ContextTranscriptFile) -> ContextHarnessPass {
        extract(ContextJSONLReader.events(at: transcript.path))
    }
}

/// Where each harness keeps its sessions on this machine.
public struct ContextRoots: Sendable {
    public var claudeProjectsDir: URL
    public var codexSessionsDir: URL
    public var piSessionsDir: URL
    public var opencodeDataDir: URL
    public var kimiHome: URL
    public var clineDataDir: URL
    public var antigravityDir: URL

    public init(
        claudeProjectsDir: URL = ClaudeHarness.projectsDir,
        codexSessionsDir: URL = CodexHarness.sessionsDir,
        piSessionsDir: URL = PiHarness.sessionsDir,
        opencodeDataDir: URL = OpencodeHarness.defaultDataDir(),
        kimiHome: URL = KimiHarness.defaultHome(),
        clineDataDir: URL = ClineHarness.defaultDataDir(),
        antigravityDir: URL = AntigravityHarness.defaultDir()
    ) {
        self.claudeProjectsDir = claudeProjectsDir
        self.codexSessionsDir = codexSessionsDir
        self.piSessionsDir = piSessionsDir
        self.opencodeDataDir = opencodeDataDir
        self.kimiHome = kimiHome
        self.clineDataDir = clineDataDir
        self.antigravityDir = antigravityDir
    }

    /// Every root where each harness puts it by default under `home`,
    /// ignoring environment overrides.
    public init(home: URL) {
        self.init(
            claudeProjectsDir: home.appendingPathComponent(".claude/projects"),
            codexSessionsDir: home.appendingPathComponent(".codex/sessions"),
            piSessionsDir: home.appendingPathComponent(".pi/agent/sessions"),
            opencodeDataDir: home.appendingPathComponent(".local/share/opencode"),
            kimiHome: home.appendingPathComponent(".kimi-code"),
            clineDataDir: home.appendingPathComponent(".cline/data"),
            antigravityDir: home.appendingPathComponent(".gemini/antigravity-cli")
        )
    }

    /// The one table of context readers. Order breaks ties when two harnesses
    /// wrote at the same moment.
    public var readers: [any ContextHarnessReader] {
        let claude = claudeProjectsDir, codex = codexSessionsDir, pi = piSessionsDir
        return [
            JSONLHarnessReader(
                harness: .claude,
                discover: { ClaudeHarness.recentTranscripts(for: $0, projectsDir: claude, limit: $1, fileManager: $2) },
                extract: ClaudeHarness.extract),
            JSONLHarnessReader(
                harness: .codex,
                discover: { CodexHarness.recentTranscripts(for: $0, sessionsDir: codex, limit: $1, fileManager: $2) },
                extract: CodexHarness.extract),
            JSONLHarnessReader(
                harness: .pi,
                discover: { PiHarness.recentTranscripts(for: $0, sessionsDir: pi, limit: $1, fileManager: $2) },
                extract: PiHarness.extract),
            OpencodeHarness(dataDir: opencodeDataDir),
            KimiHarness(home: kimiHome),
            ClineHarness(dataDir: clineDataDir),
            AntigravityHarness(dir: antigravityDir),
        ]
    }

    /// The harnesses this machine can read context for.
    public static let supportedHarnesses: Set<HarnessID> = Set(
        ContextRoots(home: URL(fileURLWithPath: "/")).readers.map(\.harness))
}

private nonisolated(unsafe) let contextISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

/// Epoch milliseconds as the ISO text every blob timestamp uses, so they
/// compare as strings across harnesses.
func contextISO(milliseconds: Double) -> String {
    contextISOFormatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
}

func contextISO(_ date: Date) -> String {
    contextISOFormatter.string(from: date)
}

/// A JSON object or array as compact text, keys sorted, for a blob.
func contextJSONText(_ value: Any?) -> String? {
    guard let value, JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    else { return nil }
    return String(data: data, encoding: .utf8)
}

/// The first line of a subagent's task, short enough for a panel row.
func contextLabel(_ value: String?, limit: Int = 56) -> String {
    let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
    return firstLine.count <= limit ? firstLine : String(firstLine.prefix(limit - 1)) + "…"
}

/// Up to `limit` newest of `files`, dropped to the single newest when none
/// was touched in the last `maxAgeHours`, as `ContextTranscriptDiscovery`
/// does for a folder of transcripts.
func contextRecent(
    _ files: [ContextTranscriptFile], limit: Int, maxAgeHours: Double = 12
) -> [ContextTranscriptFile] {
    let sorted = files.sorted { $0.modified > $1.modified }
    let floor = Date().addingTimeInterval(-maxAgeHours * 3600)
    let fresh = sorted.filter { $0.modified >= floor }
    return Array((fresh.isEmpty ? Array(sorted.prefix(1)) : fresh).prefix(limit))
}

func contextModified(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
}

/// A start with no end for longer than this is a session that died, not
/// work still going: without the cutoff it would show as running forever.
func contextIsStale(_ started: String, newest: String, after limit: TimeInterval = 6 * 3600) -> Bool {
    guard let began = ContextTimestamp.parse(started), let last = ContextTimestamp.parse(newest) else { return false }
    return last.timeIntervalSince(began) > limit
}
