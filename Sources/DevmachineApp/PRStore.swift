import Foundation
import DevmachineCore

@MainActor
final class PRStore: ObservableObject {
    @Published var forest: [(pr: PullRequest, depth: Int)] = []
    @Published var owners: [String] = [allOwnersSentinel]
    @Published var selectedOwner: String = allOwnersSentinel
    @Published var openCount: Int = 0
    @Published var errorText: String?
    @Published var isLoading = false
    @Published var favorites: [String] = UserDefaults.standard.stringArray(forKey: "favoriteOwners") ?? []

    // Owners as shown in the dropdown: "All" first, then favorites, then the rest.
    var orderedOwners: [String] { orderOwners(owners, favorites: favorites) }

    func isFavorite(_ owner: String) -> Bool { favorites.contains(owner) }

    func toggleFavorite(_ owner: String) {
        guard owner != allOwnersSentinel, !owner.isEmpty else { return }
        if let i = favorites.firstIndex(of: owner) {
            favorites.remove(at: i)
        } else {
            favorites.append(owner)
        }
        UserDefaults.standard.set(favorites, forKey: "favoriteOwners")
    }

    private let client: GHClient
    private var myLogin: String?
    private nonisolated(unsafe) var timer: Timer?
    // Every refresh gets a generation number; only the newest one is allowed to
    // mutate state. This makes switching owners cancel-and-supersede an
    // in-flight load instead of being dropped by it (or clobbering it later).
    private var coordinator = RefreshCoordinator()
    private nonisolated(unsafe) var refreshTask: Task<Void, Never>?

    // Last-seen results per owner, so switching shows the cached list instantly
    // instead of a blank loading screen for an owner already seen this session.
    private var cache: [String: [PullRequest]] = [:]

    private var isRefreshing = false

    init(client: GHClient = GHClient()) {
        self.client = client
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfIdle() }
        }
    }

    // A cycle slower than the 60s tick would otherwise overlap with the next
    // one and compound the number of `gh` processes.
    func refreshIfIdle() {
        guard !isRefreshing else { return }
        refresh()
    }

    deinit {
        timer?.invalidate()
        refreshTask?.cancel()
    }

    func select(_ owner: String) {
        guard owner != selectedOwner else { return }
        selectedOwner = owner
        errorText = nil
        if let cached = cache[owner] {
            forest = buildStackForest(cached)
            openCount = cached.count
        }
        refresh()
    }

    func refresh() {
        let gen = coordinator.begin()
        let owner = selectedOwner
        refreshTask?.cancel()
        isLoading = true
        isRefreshing = true
        let client = self.client
        let knownLogin = myLogin

        refreshTask = Task {
            do {
                let login = try await Self.resolveLogin(client: client, known: knownLogin)
                let search = try await Task.detached { try client.search(owner: owner) }.value
                let details = try await Self.enrich(search, client: client)

                guard coordinator.mayApply(gen) else { return }
                self.myLogin = login
                self.cache[owner] = details

                let resultOwners = search.map {
                    $0.repository.nameWithOwner.split(separator: "/").first.map(String.init) ?? ""
                }
                let orgs = (try? await Task.detached { try client.orgs() }.value) ?? []
                guard coordinator.mayApply(gen) else { return }

                self.owners = mergeOwners(orgs: orgs, resultOwners: resultOwners, myLogin: login)
                self.forest = buildStackForest(details)
                self.openCount = details.count
                self.errorText = nil
            } catch {
                guard coordinator.mayApply(gen) else { return }
                // Keep the cached list on screen; only surface the error if we
                // have nothing to show for this owner.
                if forest.isEmpty {
                    self.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            if coordinator.mayApply(gen) {
                self.isLoading = false
                self.isRefreshing = false
            }
        }
    }

    private nonisolated static func resolveLogin(client: GHClient, known: String?) async throws -> String? {
        if let known { return known }
        return try? await Task.detached { try client.login() }.value
    }

    // Concurrency is bounded by the size of the group itself: `limit` tasks
    // start, and each finished one admits the next. A cancelled cycle stops
    // admitting, so it stops spawning `gh`.
    private nonisolated static func enrich(
        _ search: [SearchPR],
        client: GHClient,
        limit: Int = 6
    ) async throws -> [PullRequest] {
        try Task.checkCancellation()
        return await withTaskGroup(of: PullRequest?.self) { group in
            var next = 0
            while next < min(limit, search.count) {
                let s = search[next]
                group.addTask { await Self.detailOrNil(for: s, client: client) }
                next += 1
            }

            var result: [PullRequest] = []
            while let pr = await group.next() {
                if let pr { result.append(pr) }
                guard next < search.count, !Task.isCancelled else { continue }
                let s = search[next]
                group.addTask { await Self.detailOrNil(for: s, client: client) }
                next += 1
            }
            return result
        }
    }

    private nonisolated static func detailOrNil(for s: SearchPR, client: GHClient) async -> PullRequest? {
        guard !Task.isCancelled else { return nil }
        return try? await Task.detached { try Self.detail(for: s, client: client) }.value
    }

    private nonisolated static func detail(for s: SearchPR, client: GHClient) throws -> PullRequest {
        let repo = s.repository.nameWithOwner
        let d = try client.detail(number: s.number, repo: repo)
        return PullRequest(
            number: d.number, title: d.title, repo: repo, url: d.url,
            isDraft: d.isDraft, reviewDecision: d.reviewDecision ?? "",
            headRefName: d.headRefName, baseRefName: d.baseRefName,
            ci: rollupState(from: d.statusCheckRollup ?? [])
        )
    }
}
