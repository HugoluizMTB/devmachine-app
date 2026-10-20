import AppKit
import DevmachineCore

/// The widget catalog as the CLI resolves it. A failed read keeps the last
/// good catalog, marked stale, and reads again on `CatalogRetrySchedule`
/// until one works. With none yet, a network failure is read again on
/// `RetryPolicy.downloads` while the state stays `.loading`, whether or not
/// a board waits; only then does Home say it could not fetch packages.
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
    private nonisolated(unsafe) var retry: Task<Void, Never>?
    private var retryFailures = 0
    private nonisolated(unsafe) var quickRetry: Task<Void, Never>?
    /// Failed reads in a row while there is no catalog yet.
    private var firstReadFailures = 0
    private var catalogWaiters: Set<String> = []
    private nonisolated(unsafe) var quitObserver: NSObjectProtocol?
    private var quitting = false

    init(
        read: @escaping @Sendable () throws -> WidgetCatalog = { try WidgetCatalogStore.liveRead() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.read = read
        self.sleep = sleep
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopForQuit() }
        }
    }

    deinit {
        retry?.cancel()
        quickRetry?.cancel()
        if let quitObserver { NotificationCenter.default.removeObserver(quitObserver) }
    }

    /// Only quit drops the observer: a plain `stopRetrying` after a good read
    /// must still let a later stale spell stop at quit.
    func stopForQuit() {
        quitting = true
        stopRetrying()
        if let quitObserver { NotificationCenter.default.removeObserver(quitObserver) }
        quitObserver = nil
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

    /// Retry, a board change, the gallery opening: a fresh set of attempts.
    func reloadSoon() {
        if quickRetry == nil { firstReadFailures = 0 }
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
            let message = error.localizedDescription
            if catalog == nil, retryQuickly(after: message) { break }
            if let current = catalog, !current.isStale { catalog = current.stale() }
            state = .failed(message)
            scheduleRetry()
        }
        if again {
            again = false
            await reload()
        }
    }

    /// No catalog yet and the network failed: read again soon, up to
    /// `RetryPolicy.downloads.maxAttempts` reads, still `.loading`.
    private func retryQuickly(after message: String) -> Bool {
        guard !quitting else { return false }
        if quickRetry != nil {
            state = .loading
            return true
        }
        firstReadFailures += 1
        guard let delay = RetryPolicy.downloads.delay(afterFailedAttempts: firstReadFailures, output: [message])
        else { return false }
        state = .loading
        let sleep = self.sleep
        quickRetry = Task { [weak self] in
            await sleep(delay)
            guard !Task.isCancelled, let self else { return }
            self.quickRetry = nil
            await self.reload()
        }
        return true
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
            stopSlowRetry()
        } else if catalog == nil, case .failed = state {
            scheduleRetry()
        }
    }

    var isWaitedFor: Bool { !catalogWaiters.isEmpty }

    /// One pending retry serves Home and both sidebars; a failure while it
    /// waits does not start a second one.
    private func scheduleRetry() {
        guard retry == nil, needsRetry, !quitting else { return }
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
        stopSlowRetry()
        quickRetry?.cancel()
        quickRetry = nil
        firstReadFailures = 0
    }

    private func stopSlowRetry() {
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
