import DevmachineCore

struct HarnessRegistry: Sendable {
    let adapters: [any CodingHarnessAdapter]

    init(adapters: [any CodingHarnessAdapter]) {
        self.adapters = adapters
    }

    func adapter(for id: HarnessID) -> (any CodingHarnessAdapter)? {
        adapters.first { $0.id == id }
    }

    static let builtIn = HarnessRegistry(adapters: [
        ClaudeHarnessAdapter(),
        CodexHarnessAdapter()
    ])
}
