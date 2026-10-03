import Foundation

/// A coding harness `devmachine skills add --agent` links the skills for.
/// The skills land in `~/.agents/skills` whatever is chosen, so a harness
/// installed later finds them; `--agent` works for one not installed yet.
public struct SkillAgent: Equatable, Sendable, Identifiable {
    public let harness: HarnessID
    /// The name `--agent` takes.
    public let id: String
    public let name: String

    public init(harness: HarnessID, id: String, name: String) {
        self.harness = harness
        self.id = id
        self.name = name
    }

    /// What the CLI knows of a harness: its `--agent` name, the folder
    /// `skills add` finds it by, and the first release that accepts it.
    struct CLIAgent {
        let name: String
        let folder: String
        let since: SemanticVersion?
    }

    /// Antigravity, Kimi and Cline came after 0.7.27: an older CLI refuses
    /// the whole `skills add` with "unknown agent".
    static let newerAgentsCLI = SemanticVersion(major: 0, minor: 7, patch: 28)

    static let cliAgents: [HarnessID: CLIAgent] = [
        .claude: CLIAgent(name: "claude", folder: ".claude", since: nil),
        .codex: CLIAgent(name: "codex", folder: ".codex", since: nil),
        .pi: CLIAgent(name: "pi", folder: ".pi", since: nil),
        .opencode: CLIAgent(name: "opencode", folder: ".config/opencode", since: nil),
        .antigravity: CLIAgent(name: "antigravity", folder: ".gemini/antigravity-cli", since: newerAgentsCLI),
        .kimi: CLIAgent(name: "kimi", folder: ".kimi-code", since: newerAgentsCLI),
        .cline: CLIAgent(name: "cline", folder: ".cline", since: newerAgentsCLI),
    ]

    /// The given harnesses, in their order, that this CLI's `skills add`
    /// accepts. An unread version gets only the agents every release takes.
    public static func options(
        harnesses: [(id: HarnessID, title: String)], cliVersion: SemanticVersion?
    ) -> [SkillAgent] {
        harnesses.compactMap { harness in
            guard let agent = cliAgents[harness.id] else { return nil }
            if let since = agent.since {
                guard let cliVersion, cliVersion >= since else { return nil }
            }
            return SkillAgent(harness: harness.id, id: agent.name, name: harness.title)
        }
    }

    /// The options for the given harnesses, plus the ones whose folder this
    /// home has (what `skills add` itself would find), in the options' order.
    public static func preselected(
        from options: [SkillAgent], harnesses: [HarnessID], home: String, isDirectory: (String) -> Bool
    ) -> [SkillAgent] {
        options.filter { option in
            if harnesses.contains(option.harness) { return true }
            guard let folder = cliAgents[option.harness]?.folder else { return false }
            return isDirectory(home + "/" + folder)
        }
    }
}
