import DevmachineCore

/// Provider availability is independent of whether a session can show Files/Git.
struct ContextFacade: Sendable {
    let source: any ContextSource

    func supports(_ harnesses: Set<HarnessID>) -> Bool {
        // This facade serves both the local native engine and the remote
        // package call, which still answers for Claude only — so the gate
        // stays Claude-only even though the native engine itself also reads
        // Codex and Pi transcripts.
        harnesses.contains(.claude)
    }

    func context(for target: CommandTarget, harnesses: Set<HarnessID>, settings: AppSettings) throws -> ContextState? {
        guard supports(harnesses) else { return nil }
        return try source.context(for: target, settings: settings)
    }
}
