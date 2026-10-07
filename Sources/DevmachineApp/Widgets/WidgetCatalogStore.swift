import AppKit
import DevmachineCore

/// The widget catalog as the CLI resolves it. A failed read keeps the last
/// good catalog, marked stale, and reads again on `CatalogRetrySchedule`
/// until one works; with none, Home says it could not fetch packages.
@MainActor
final class WidgetCatalogStore: ObservableObject {
    static let shared = WidgetCatalogStore()

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var catalog: WidgetCatalog?

    private let read: @Sendable () throws -> WidgetCatalog
    private var running = false
    private var again = false
    private var pinned = false
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var retry: Task<Void, Never>?
    private var retryFailures = 0
    private var catalogWaiters: Set<String> = []
    private var quitObserver: NSObjectProtocol?

    init(
        read: @escaping @Sendable () throws -> WidgetCatalog = { try WidgetCatalogStore.liveRead() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.read = read
        self.sleep = sleep
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRetrying() }
        }
    }

    nonisolated static func liveRead() throws -> WidgetCatalog {
        let data = try DevmachineCLI.resolve().widgetsList()
        do {
            return try WidgetCatalog.decode(data)
        } catch {
            throw DevmachineCLIError.commandFailed(
                "devmachine widgets list printed JSON this app cannot read: \(error)")
        }
    }

    func reloadSoon() {
        Task { await reload() }
    }

    /// Home and both sidebars start together; the state turns `.loading`
    /// before the task exists, so only the first of them reads the catalog.
    func reloadIfIdle() {
        guard state == .idle, !pinned else { return }
        state = .loading
        Task { await reload() }
    }

    func reload() async {
        guard !pinned else { return }
        guard !running else {
            again = true
            return
        }
        running = true
        if catalog == nil { state = .loading }
        let read = self.read
        let result = await Task.detached { Result { try read() } }.value
        running = false
        switch result {
        case let .success(next):
            if catalog != next { catalog = next }
            state = .loaded
            stopRetrying()
        case let .failure(error):
            if let current = catalog, !current.isStale { catalog = current.stale() }
            state = .failed(error.localizedDescription)
            scheduleRetry()
        }
        if again {
            again = false
            await reload()
        }
    }

    /// A stale catalog is always read again; with none yet, only while a
    /// board holds a widget waiting for it, so an app without the CLI stays quiet.
    private var needsRetry: Bool {
        catalog?.isStale == true || (catalog == nil && !catalogWaiters.isEmpty)
    }

    /// Each board says whether it holds a widget that waits for the catalog.
    func setWaitsForCatalog(_ waits: Bool, board: String) {
        if waits { catalogWaiters.insert(board) } else { catalogWaiters.remove(board) }
        if !needsRetry {
            stopRetrying()
        } else if case .failed = state {
            scheduleRetry()
        }
    }

    var isWaitedFor: Bool { !catalogWaiters.isEmpty }

    /// One pending retry serves Home and both sidebars; a failure while it
    /// waits does not start a second one.
    private func scheduleRetry() {
        guard retry == nil, needsRetry else { return }
        retryFailures += 1
        guard let delay = CatalogRetrySchedule.delay(afterFailures: retryFailures) else { return }
        let sleep = self.sleep
        retry = Task { [weak self] in
            await sleep(delay)
            guard !Task.isCancelled, let self else { return }
            self.retry = nil
            guard self.needsRetry else { return }
            await self.reload()
        }
    }

    func stopRetrying() {
        retry?.cancel()
        retry = nil
        retryFailures = 0
    }

    func seed(_ catalog: WidgetCatalog) {
        stopRetrying()
        self.catalog = catalog
        state = .loaded
    }

    /// Demo mode: the catalog stays this one, and the CLI is never asked.
    func pin(_ catalog: WidgetCatalog) {
        seed(catalog)
        pinned = true
    }
}
