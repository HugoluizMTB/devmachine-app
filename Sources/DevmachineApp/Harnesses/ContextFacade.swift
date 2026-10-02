import DevmachineCore

/// Provider availability is independent of whether a session can show Files/Git.
struct ContextFacade: Sendable {
    let source: any ContextSource
    /// The harnesses whose transcripts have a reader. The native engine
    /// reads them on this Mac, and the remote `devmachine-infer` answers
    /// for the same harnesses with the same ids.
    var supported: Set<HarnessID> = ContextRoots.supportedHarnesses

    func supports(_ harnesses: Set<HarnessID>) -> Bool {
        !harnesses.isDisjoint(with: supported)
    }

    func context(for target: CommandTarget, harnesses: Set<HarnessID>, settings: AppSettings) throws -> ContextState? {
        guard supports(harnesses) else { return nil }
        return try source.context(for: target, harnesses: harnesses, settings: settings)
    }
}
