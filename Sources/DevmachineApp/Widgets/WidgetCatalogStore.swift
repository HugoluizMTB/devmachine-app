import Foundation
import DevmachineCore

/// The widget catalog as the CLI resolves it. A failed read keeps the last
/// good catalog; with none, Home says it could not fetch packages.
@MainActor
final class WidgetCatalogStore: ObservableObject {
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

    func reload() async {
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
}
