import Foundation

/// Picks which harness a local session belongs to: the pane's current
/// command when known, else whichever harness has the most recently
/// modified transcript for this project directory.
public struct ContextRoots: Sendable {
    public var claudeProjectsDir: URL
    public var codexSessionsDir: URL
    public var piSessionsDir: URL

    public init(
        claudeProjectsDir: URL = ClaudeHarness.projectsDir,
        codexSessionsDir: URL = CodexHarness.sessionsDir,
        piSessionsDir: URL = PiHarness.sessionsDir
    ) {
        self.claudeProjectsDir = claudeProjectsDir
        self.codexSessionsDir = codexSessionsDir
        self.piSessionsDir = piSessionsDir
    }
}

public enum ContextHarnessDetection {
    public static func detect(
        project: URL, paneCommand: String?, roots: ContextRoots = ContextRoots(),
        fileManager: FileManager = .default
    ) -> (harness: HarnessID, transcripts: [ContextTranscriptFile])? {
        func transcripts(for harness: HarnessID) -> [ContextTranscriptFile] {
            switch harness {
            case .claude:
                return ClaudeHarness.recentTranscripts(
                    for: project, projectsDir: roots.claudeProjectsDir, fileManager: fileManager
                )
            case .codex:
                return CodexHarness.recentTranscripts(
                    for: project, sessionsDir: roots.codexSessionsDir, fileManager: fileManager
                )
            case .pi:
                return PiHarness.recentTranscripts(
                    for: project, sessionsDir: roots.piSessionsDir, fileManager: fileManager
                )
            default:
                return []
            }
        }

        if let paneCommand {
            let lowered = paneCommand.lowercased()
            let named: HarnessID? = lowered.contains("claude") ? .claude
                : lowered.contains("codex") ? .codex
                : lowered.contains("pi") ? .pi
                : nil
            if let named {
                let files = transcripts(for: named)
                if !files.isEmpty { return (named, files) }
            }
        }

        let claude = transcripts(for: .claude)
        let codex = transcripts(for: .codex)
        let pi = transcripts(for: .pi)

        let candidates: [(HarnessID, [ContextTranscriptFile])] = [(.claude, claude), (.codex, codex), (.pi, pi)]
        let withNewest = candidates.compactMap { harness, files -> (HarnessID, [ContextTranscriptFile], Date)? in
            guard let newest = files.first?.modified else { return nil }
            return (harness, files, newest)
        }
        guard let best = withNewest.max(by: { $0.2 < $1.2 }) else { return nil }
        return (best.0, best.1)
    }
}
