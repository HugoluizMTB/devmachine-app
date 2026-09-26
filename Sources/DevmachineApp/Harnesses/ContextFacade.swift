import DevmachineCore

/// Provider availability is independent of whether a session can show Files/Git.
struct ContextFacade: Sendable {
    let source: any ContextSource

    func supports(_ harnesses: Set<HarnessID>) -> Bool {
        // The current inference engine supplies Claude context only.
        harnesses.contains(.claude)
    }

    func context(for target: CommandTarget, harnesses: Set<HarnessID>, settings: AppSettings) throws -> ContextState? {
        guard supports(harnesses) else { return nil }
        return try source.context(for: target, settings: settings)
    }
}
