import Foundation
import DevmachineCore

/// The widget catalog as the CLI resolves it. A failed read keeps the last
/// good catalog, marked stale; with none, Home says it could not fetch packages.
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

    init(read: @escaping @Sendable () throws -> WidgetCatalog = { try WidgetCatalogStore.liveRead() }) {
        self.read = read
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
        case let .failure(error):
            if let current = catalog, !current.isStale { catalog = current.stale() }
            state = .failed(error.localizedDescription)
        }
        if again {
            again = false
            await reload()
        }
    }

    func seed(_ catalog: WidgetCatalog) {
        self.catalog = catalog
        state = .loaded
    }

    /// Demo mode: the catalog stays this one, and the CLI is never asked.
    func pin(_ catalog: WidgetCatalog) {
        seed(catalog)
        pinned = true
    }
}
