import Foundation

struct ContextState: Codable, Equatable, Sendable {
    struct Plan: Codable, Equatable, Sendable {
        struct Item: Codable, Equatable, Sendable { let text: String; let state: String }
        let title: String; let source: String; let done: Int; let total: Int; let items: [Item]
    }
    struct PR: Codable, Equatable, Sendable, Identifiable {
        let number: Int; let repo: String; let title: String; let url: String
        let ci: String; let review: String; let state: String
        /// Two repositories can share a number, so the number alone is not an
        /// identity: a list keyed by it renders one row twice.
        var id: String { "\(repo)#\(number)" }
    }
    struct Link: Codable, Equatable, Sendable { let url: String; let label: String; let kind: String }
    struct Agent: Codable, Equatable, Sendable { let label: String; let status: String }

    let cwd: String
    let isClaude: Bool
    let updatedAt: String
    let plan: Plan?
    let prs: [PR]
    let links: [Link]
    let agents: [Agent]
    let monitors: [Agent]
    let shells: [Agent]

    enum CodingKeys: String, CodingKey {
        case cwd, isClaude, updatedAt, plan, prs, links, agents, monitors, shells
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cwd = try c.decode(String.self, forKey: .cwd)
        isClaude = try c.decode(Bool.self, forKey: .isClaude)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        plan = try c.decodeIfPresent(Plan.self, forKey: .plan)
        prs = try c.decode([PR].self, forKey: .prs)
        links = try c.decode([Link].self, forKey: .links)
        agents = try c.decodeIfPresent([Agent].self, forKey: .agents) ?? []
        monitors = try c.decodeIfPresent([Agent].self, forKey: .monitors) ?? []
        shells = try c.decodeIfPresent([Agent].self, forKey: .shells) ?? []
    }

    init(cwd: String, isClaude: Bool, updatedAt: String, plan: Plan?, prs: [PR], links: [Link],
         agents: [Agent] = [], monitors: [Agent] = [], shells: [Agent] = []) {
        self.cwd = cwd
        self.isClaude = isClaude
        self.updatedAt = updatedAt
        self.plan = plan
        self.prs = prs
        self.links = links
        self.agents = agents
        self.monitors = monitors
        self.shells = shells
    }
}
