import SwiftUI

public struct HarnessUsageState: Equatable, Sendable, Identifiable {
    public var id: String { harnessID }
    public let harnessID: String
    public var snapshot: HarnessUsageSnapshot?
    public var errorText: String?
    public var errorKind: HarnessUsageErrorKind?
    public var isLoading: Bool
    public var refreshedAt: Date?

    public init(
        harnessID: String,
        snapshot: HarnessUsageSnapshot? = nil,
        errorText: String? = nil,
        errorKind: HarnessUsageErrorKind? = nil,
        isLoading: Bool = false,
        refreshedAt: Date? = nil
    ) {
        self.harnessID = harnessID
        self.snapshot = snapshot
        self.errorText = errorText
        self.errorKind = errorKind ?? errorText.map(HarnessUsageErrorKind.init(text:))
        self.isLoading = isLoading
        self.refreshedAt = refreshedAt
    }

    /// Nothing to show yet: no snapshot and no error. A refresh keeps the
    /// last snapshot, so the skeleton never comes back once one arrived.
    public var showsSkeleton: Bool { snapshot == nil && errorText == nil }
}

@MainActor
public final class HarnessUsageStore: ObservableObject {
    @Published public private(set) var states: [HarnessUsageState]

    private var providers: [any HarnessUsageProvider]
    private let pollSeconds: TimeInterval
    private var inFlight: Set<String> = []
    private var generation = 0
    private nonisolated(unsafe) var timer: Timer?
    private var observers = 0

    public init(providers: [any HarnessUsageProvider], pollSeconds: TimeInterval = 60) {
        self.providers = providers
        self.pollSeconds = pollSeconds
        states = providers.map { HarnessUsageState(harnessID: $0.harnessID) }
    }

    public convenience init(
        provider: any UsageProvider = DefaultUsageProvider(),
        config: ClaudeUsageConfig = .init()
    ) {
        self.init(
            providers: [ClaudeUsageProvider(provider: provider)],
            pollSeconds: config.usagePollSeconds)
    }

    deinit { timer?.invalidate() }

    public var isPolling: Bool { timer != nil }
    public var observerCount: Int { observers }
    public var isObserved: Bool { observers > 0 }

    public func state(for harnessID: String) -> HarnessUsageState? {
        states.first { $0.harnessID == harnessID }
    }

    public func configure(providers: [any HarnessUsageProvider]) {
        generation += 1
        inFlight.removeAll()
        self.providers = providers
        let previous = Dictionary(uniqueKeysWithValues: states.map { ($0.harnessID, $0) })
        let next = providers.map { previous[$0.harnessID] ?? HarnessUsageState(harnessID: $0.harnessID) }
        if next != states { states = next }
    }

    public func beginObserving() {
        observers += 1
        guard observers == 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
    }

    public func endObserving() {
        guard observers > 0 else { return }
        observers -= 1
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    public func refresh(force: Bool = false) {
        for provider in providers { refresh(provider, force: force) }
    }

    public func refreshStats(force: Bool = false) {
        refresh(force: force)
    }

    private func refresh(_ provider: any HarnessUsageProvider, force: Bool) {
        let id = provider.harnessID
        guard !inFlight.contains(id), let index = states.firstIndex(where: { $0.harnessID == id }) else {
            return
        }
        if !force, let refreshedAt = states[index].refreshedAt,
           Date().timeIntervalSince(refreshedAt) < pollSeconds {
            return
        }

        inFlight.insert(id)
        updateState(at: index) {
            $0.isLoading = true
            $0.errorText = nil
            $0.errorKind = nil
        }
        let previous = states[index].snapshot
        let requestedGeneration = generation

        Task.detached {
            let result = Result { try provider.fetchSnapshot(previous: previous) }
            await MainActor.run {
                self.inFlight.remove(id)
                guard self.generation == requestedGeneration else { return }
                guard let current = self.states.firstIndex(where: { $0.harnessID == id }) else { return }
                self.updateState(at: current) { state in
                    state.isLoading = false
                    state.refreshedAt = Date()
                    switch result {
                    case let .success(snapshot):
                        if state.snapshot != snapshot { state.snapshot = snapshot }
                        state.errorText = nil
                        state.errorKind = nil
                    case let .failure(error):
                        state.errorText = HarnessUsageErrorKind.text(of: error)
                        state.errorKind = HarnessUsageErrorKind(error: error)
                    }
                }
            }
        }
    }

    private func updateState(at index: Int, change: (inout HarnessUsageState) -> Void) {
        var next = states[index]
        change(&next)
        guard next != states[index] else { return }
        states[index] = next
    }

    public var blocks: [UsageBlock] { states.first?.snapshot?.blocks ?? [] }
    public var stats: UsageStats? { states.first?.snapshot?.stats }
    public var planName: String { states.first?.snapshot?.planName ?? "" }
    public var errorText: String? { states.first?.errorText }
    public var isLoading: Bool { states.first?.isLoading ?? false }
    public var refreshedAt: Date? { states.first?.refreshedAt }
}
