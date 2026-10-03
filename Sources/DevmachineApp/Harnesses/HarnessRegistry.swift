import DevmachineCore

struct HarnessRegistry: Sendable {
    let adapters: [any CodingHarnessAdapter]

    init(adapters: [any CodingHarnessAdapter]) {
        self.adapters = adapters
    }

    func adapter(for id: HarnessID) -> (any CodingHarnessAdapter)? {
        adapters.first { $0.id == id }
    }

    /// Every program name each harness runs as, enabled or not.
    var processNames: [HarnessID: Set<String>] {
        Dictionary(adapters.map { ($0.id, $0.processNames) }, uniquingKeysWith: { $0.union($1) })
    }

    static let builtIn = HarnessRegistry(adapters: [
        ClaudeHarnessAdapter(),
        CodexHarnessAdapter(),
        BasicHarnessAdapter.pi,
        BasicHarnessAdapter.antigravity,
        BasicHarnessAdapter.opencode,
        BasicHarnessAdapter.kimi,
        BasicHarnessAdapter.cline
    ])
}
