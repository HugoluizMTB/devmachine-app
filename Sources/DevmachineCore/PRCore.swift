import Foundation

// Pure model + logic. Foundation only (no SwiftUI/AppKit) so it links into the
// standalone test binary. UI concerns (colors, glyphs) live in App.swift as
// extensions.

public enum CIState: String, Sendable {
    case success, failure, pending, none
}

public enum RowState {
    case draft, changesRequested, approved, open

    public var label: String {
        switch self {
        case .draft: return "Draft"
        case .changesRequested: return "Changes requested"
        case .approved: return "Approved"
        case .open: return "Open"
        }
    }
}

public struct PullRequest: Identifiable, Sendable {
    public let number: Int
    public let title: String
    public let repo: String        // owner/repo
    public let url: String
    public let isDraft: Bool
    public let reviewDecision: String
    public let headRefName: String
    public let baseRefName: String
    public let ci: CIState

    public init(number: Int, title: String, repo: String, url: String, isDraft: Bool,
                reviewDecision: String, headRefName: String, baseRefName: String, ci: CIState) {
        self.number = number
        self.title = title
        self.repo = repo
        self.url = url
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.ci = ci
    }

    public var id: String { "\(repo)#\(number)" }
    public var owner: String { repo.split(separator: "/").first.map(String.init) ?? repo }

    public var rowState: RowState {
        if isDraft { return .draft }
        switch reviewDecision {
        case "CHANGES_REQUESTED": return .changesRequested
        case "APPROVED": return .approved
        default: return .open
        }
    }
}

public struct SearchPR: Decodable, Sendable {
    public struct Repo: Decodable, Sendable {
        public let nameWithOwner: String
    }
    public let number: Int
    public let title: String
    public let isDraft: Bool
    public let repository: Repo
}

public struct CheckContext: Decodable, Sendable {
    public let status: String?
    public let conclusion: String?
    public let state: String?

    public init(status: String?, conclusion: String?, state: String?) {
        self.status = status
        self.conclusion = conclusion
        self.state = state
    }
}

public struct PRDetail: Decodable, Sendable {
    public let number: Int
    public let title: String
    public let url: String
    public let isDraft: Bool
    public let reviewDecision: String?
    public let headRefName: String
    public let baseRefName: String
    public let statusCheckRollup: [CheckContext]?
}

public func decodeSearchPRs(_ data: Data) throws -> [SearchPR] {
    try JSONDecoder().decode([SearchPR].self, from: data)
}

public func decodePRDetail(_ data: Data) throws -> PRDetail {
    try JSONDecoder().decode(PRDetail.self, from: data)
}

// GitHub reports checks in two shapes: modern CheckRun (status + conclusion)
// and legacy StatusContext (state). Fold both into one 4-way rollup. A single
// failing/errored context wins; otherwise anything still running is pending;
// otherwise at least one success is success; an empty list is none.
public func rollupState(from contexts: [CheckContext]) -> CIState {
    if contexts.isEmpty { return .none }

    let failing: Set<String> = ["FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED", "CANCELLED"]
    let running: Set<String> = ["QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED", "EXPECTED"]

    var anyPending = false
    var anySuccess = false

    for c in contexts {
        let conclusion = c.conclusion?.uppercased() ?? ""
        let state = c.state?.uppercased() ?? ""
        let status = c.status?.uppercased() ?? ""

        if failing.contains(conclusion) || failing.contains(state) {
            return .failure
        }
        if conclusion == "SUCCESS" || state == "SUCCESS" {
            anySuccess = true
        }
        // A CheckRun that hasn't completed has no conclusion — judge it by
        // status. Legacy contexts use state == PENDING.
        if conclusion.isEmpty && running.contains(status) { anyPending = true }
        if running.contains(state) { anyPending = true }
    }

    if anyPending { return .pending }
    if anySuccess { return .success }
    return .none
}

// "All" plus every distinct owner we can reach: the viewer's own login, orgs
// with visible membership, and owners that showed up in the actual results
// (which recovers private-membership orgs missing from `gh api user/orgs`).
public let allOwnersSentinel = "All"

public func mergeOwners(orgs: [String], resultOwners: [String], myLogin: String?) -> [String] {
    var set = Set<String>()
    orgs.forEach { if !$0.isEmpty { set.insert($0) } }
    resultOwners.forEach { if !$0.isEmpty { set.insert($0) } }
    if let me = myLogin, !me.isEmpty { set.insert(me) }
    return [allOwnersSentinel] + set.sorted { $0.lowercased() < $1.lowercased() }
}

// Reorder the dropdown so favorites are quick to reach: "All" stays pinned
// first, then favorited owners (in the list's existing order), then the rest.
// Favorites not present in `owners` (e.g. an org with no open PRs right now)
// are still surfaced so the choice never disappears.
public func orderOwners(_ owners: [String], favorites: [String]) -> [String] {
    let fav = Set(favorites)
    let present = owners.filter { $0 != allOwnersSentinel }
    let favInList = present.filter { fav.contains($0) }
    let missingFavs = favorites.filter { !present.contains($0) && $0 != allOwnersSentinel }
    let rest = present.filter { !fav.contains($0) }
    return [allOwnersSentinel] + favInList + missingFavs + rest
}

// Serializes overlapping refreshes: each begin() hands out a higher generation,
// and only the latest generation is allowed to write results back. Switching
// owners starts a new generation, so an in-flight load can neither block the
// switch nor clobber its results when it finally lands.
public struct RefreshCoordinator {
    public private(set) var generation = 0

    public init() {}

    public mutating func begin() -> Int {
        generation += 1
        return generation
    }
    public func mayApply(_ gen: Int) -> Bool { gen == generation }
}

// Order PRs so stacked chains read as a tree. Within one repo, PR B is a child
// of PR A when B.baseRefName == A.headRefName. Returns (pr, depth) in
// depth-first order; roots (base not produced by any sibling) sorted by number.
public func buildStackForest(_ prs: [PullRequest]) -> [(pr: PullRequest, depth: Int)] {
    var out: [(PullRequest, Int)] = []
    let byRepo = Dictionary(grouping: prs, by: { $0.repo })

    for repo in byRepo.keys.sorted() {
        let group = byRepo[repo]!
        let heads = Set(group.map { $0.headRefName })
        var childrenOf: [String: [PullRequest]] = [:] // parent headRefName -> children
        var roots: [PullRequest] = []

        for pr in group {
            if heads.contains(pr.baseRefName) {
                childrenOf[pr.baseRefName, default: []].append(pr)
            } else {
                roots.append(pr)
            }
        }

        var visited = Set<Int>()
        func walk(_ pr: PullRequest, _ depth: Int) {
            guard !visited.contains(pr.number) else { return }
            visited.insert(pr.number)
            out.append((pr, depth))
            let kids = (childrenOf[pr.headRefName] ?? []).sorted { $0.number < $1.number }
            for k in kids { walk(k, depth + 1) }
        }
        for r in roots.sorted(by: { $0.number < $1.number }) { walk(r, 0) }
        // Any PR left unvisited (e.g. a cycle) still gets listed flat.
        for pr in group.sorted(by: { $0.number < $1.number }) where !visited.contains(pr.number) {
            walk(pr, 0)
        }
    }
    return out
}
