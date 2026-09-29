import Foundation

/// The native engine's output. Same JSON shape as the `devmachine-infer`
/// Python package (`cwd, isClaude, harness, updatedAt, plan, prs, links,
/// agents, monitors, shells`) so the app's existing `ContextState` decoder
/// reads it with no changes.
public struct ContextEngineResult: Codable, Equatable, Sendable {
    public struct PlanItem: Codable, Equatable, Sendable {
        public let text: String
        public let state: String

        public init(text: String, state: String) {
            self.text = text
            self.state = state
        }
    }

    public struct Plan: Codable, Equatable, Sendable {
        public let title: String
        public let source: String
        public let done: Int
        public let total: Int
        public let items: [PlanItem]

        public init(title: String, source: String, items: [PlanItem]) {
            self.title = title
            self.source = source
            self.items = items
            self.done = items.filter { $0.state == "done" }.count
            self.total = items.count
        }
    }

    public struct PR: Codable, Equatable, Sendable {
        public let number: Int
        public let repo: String
        public let title: String
        public let url: String
        public let ci: String
        public let review: String
        public let state: String
        public var threads: Int?
        public var lastSeen: String?

        public init(
            number: Int, repo: String, title: String, url: String, ci: String, review: String,
            state: String, threads: Int? = nil, lastSeen: String? = nil
        ) {
            self.number = number
            self.repo = repo
            self.title = title
            self.url = url
            self.ci = ci
            self.review = review
            self.state = state
            self.threads = threads
            self.lastSeen = lastSeen
        }
    }

    public struct Link: Codable, Equatable, Sendable {
        public let url: String
        public let label: String
        public let kind: String

        public init(url: String, label: String, kind: String) {
            self.url = url
            self.label = label
            self.kind = kind
        }
    }

    public struct Agent: Codable, Equatable, Sendable {
        public let label: String
        public let status: String

        public init(label: String, status: String) {
            self.label = label
            self.status = status
        }
    }

    public let cwd: String
    public let harness: HarnessID?
    public let isClaude: Bool
    public let updatedAt: String
    public let plan: Plan?
    public let prs: [PR]
    public let links: [Link]
    public let agents: [Agent]
    public let monitors: [Agent]
    public let shells: [Agent]

    public init(
        cwd: String, harness: HarnessID?, updatedAt: String, plan: Plan?, prs: [PR],
        links: [Link], agents: [Agent] = [], monitors: [Agent] = [], shells: [Agent] = []
    ) {
        self.cwd = cwd
        self.harness = harness
        self.isClaude = harness == .claude
        self.updatedAt = updatedAt
        self.plan = plan
        self.prs = prs
        self.links = links
        self.agents = agents
        self.monitors = monitors
        self.shells = shells
    }
}
