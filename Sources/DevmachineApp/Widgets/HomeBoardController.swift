import Foundation
import DevmachineCore
import os

enum HomeBoardError: LocalizedError, Equatable {
    case noConfiguration
    case noConfigurationFolder

    var errorDescription: String? {
        switch self {
        case .noConfiguration:
            "Home has no layout file yet: the devmachine CLI has not said where its configuration lives."
        case .noConfigurationFolder:
            "Home was not reset: the devmachine configuration folder does not exist yet."
        }
    }
}

/// Home's board: the file, the catalog that gives each entry its meaning,
/// the once-only placements, and the refresh schedule.
@MainActor
final class HomeBoardController: ObservableObject {
    static let shared = HomeBoardController()

    @Published private(set) var store: BoardStore?
    @Published private(set) var placementsError: String?
    let catalog: WidgetCatalogStore
    let runtime = WidgetRuntimeDriver()
    var defaultBoard: @MainActor () -> Board = { DefaultBoard.make(harnesses: []) }

    private let placementsFile: WidgetPlacementsFile
    private var placements: WidgetPlacements
    private var watcher: BoardFileWatcher?
    private var watchedFolder: UInt64?
    private var configObserver: NSObjectProtocol?
    private var started = false
    private var openingFromConfiguration = false
    private let configPath: @Sendable () async -> String?
    private var injectedSources: WidgetSourceController?
    private static let log = Logger(subsystem: "app.devmachine.mac", category: "widgets")

    init(
        placementsFile: WidgetPlacementsFile = WidgetPlacementsFile(fileURL: HomeBoardController.placementsURL()),
        catalog: WidgetCatalogStore = .shared,
        configPath: @escaping @Sendable () async -> String? = {
            await Task.detached { try? DevmachineCLI.resolve().configPath().path }.value
        },
        sources: WidgetSourceController? = nil
    ) {
        self.placementsFile = placementsFile
        self.placements = placementsFile.load()
        self.catalog = catalog
        self.configPath = configPath
        self.injectedSources = sources
    }

    /// Created on first use, so tests that never touch source widgets never
    /// read the real approvals file.
    var sources: WidgetSourceController {
        if let injectedSources { return injectedSources }
        let created = WidgetSourceController(runners: WidgetSourceLive.runners())
        injectedSources = created
        return created
    }

    static func placementsURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["DEVMACHINE_WIDGET_PLACEMENTS"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return WidgetPlacementsFile.defaultFileURL
    }

    func start() {
        guard !started else { return }
        started = true
        if DemoMode.isActive {
            catalog.pin(DemoData.widgetCatalog)
            open(configDirectory: DemoMode.boardsFolder)
            return
        }
        catalog.reloadIfIdle()
        observeConfiguration()
        openFromConfiguration()
    }

    /// Asks the CLI where its configuration lives; a reload asks again while
    /// no board is open, so a CLI installed after launch is picked up.
    func openFromConfiguration() {
        guard store == nil, !openingFromConfiguration else { return }
        openingFromConfiguration = true
        Task {
            let path = await configPath()
            openingFromConfiguration = false
            if let path, store == nil { open(configDirectory: path) }
        }
    }

    func open(configDirectory: String) {
        let store = BoardStore(
            fileURL: BoardStore.homeFileURL(configDirectory: configDirectory),
            makeDefault: { [weak self] in self?.defaultBoard() ?? DefaultBoard.make(harnesses: []) })
        watcher = nil
        watchedFolder = nil
        self.store = store
        store.load()
        watchIfNeeded(store)
    }

    /// After the packages change: the catalog may have new widgets, and the
    /// board file may have been rewritten.
    func reload() {
        guard started else { return }
        catalog.reloadSoon()
        reloadBoard()
    }

    private func reloadBoard() {
        guard let store else { return openFromConfiguration() }
        store.load()
        watchIfNeeded(store)
    }

    /// The watcher holds the `boards/` folder it opened, so once that folder
    /// is deleted it hears nothing more, even after a new one appears.
    private func watchIfNeeded(_ store: BoardStore) {
        let folder = Self.fileNumber(store.fileURL.deletingLastPathComponent())
        guard watcher == nil || folder != watchedFolder else { return }
        watchedFolder = folder
        watcher = folder == nil ? nil : BoardFileWatcher(fileURL: store.fileURL) { [weak self] in self?.reloadBoard() }
    }

    private static func fileNumber(_ url: URL) -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    private func observeConfiguration() {
        configObserver = NotificationCenter.default.addObserver(
            forName: ConfigDirectoryWatcher.changed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func resolution(of widget: BoardWidget) -> WidgetResolution? {
        if widget.isInline { return WidgetResolution.resolveInline(widget, catalog: catalog.catalog) }
        return catalog.catalog.map { WidgetResolution.resolve(widget, in: $0) }
    }

    func applyPlaces(canvasWidth: Int, enabledHarnesses: Set<String>) {
        guard let store, store.canEdit, let board = store.board, let catalog = catalog.catalog else { return }
        let shown = Set(board.widgets.compactMap { widget -> String? in
            guard case let .ready(resolved)? = resolution(of: widget), resolved.provider == "app/harness-usage" else { return nil }
            return resolved.arguments["harness"]
        })
        let result = WidgetPlacer.place(
            on: board, catalog: catalog, placements: placements, canvasWidth: canvasWidth,
            options: ["harnesses": enabledHarnesses.sorted()],
            isShown: { widget in WidgetPlacer.harness(of: widget).map(shown.contains) ?? false },
            isEligible: { widget in WidgetPlacer.harness(of: widget).map(enabledHarnesses.contains) ?? true })
        if result.boardChanged { store.update { $0 = result.board } }
        if result.placementsChanged { savePlacements(result.placements) }
    }

    func move(_ id: String, to frame: BoardFrame) {
        edit(id) { $0.frame = frame }
    }

    func resize(_ id: String, to frame: BoardFrame, sizes: [String]) {
        edit(id) {
            $0.frame = frame
            $0.size = CanvasLayout.sizeName(CanvasSize(w: frame.w, h: frame.h), sizes: sizes)
        }
    }

    func setPreset(_ id: String, preset: String) {
        guard let size = CanvasLayout.presetSize(preset) else { return }
        edit(id) {
            $0.frame.w = size.w
            $0.frame.h = size.h
            $0.size = preset
        }
    }

    func setMinimized(_ id: String, _ minimized: Bool) {
        edit(id) { $0.minimized = minimized }
    }

    func bringToFront(_ id: String) {
        guard let board = store?.board, let widget = board.widgets.first(where: { $0.id == id }),
              board.widgets.contains(where: { $0.id != id && $0.z >= widget.z })
        else { return }
        let top = board.topZ
        edit(id) { $0.z = top + 1 }
    }

    func remove(_ id: String) {
        store?.update { $0.widgets.removeAll { $0.id == id } }
    }

    var addBlockedReason: String? {
        HomeBoardCopy.addBlocked(isOpen: store != nil, canEdit: store?.canEdit ?? false)
    }

    @discardableResult
    func add(_ widget: CatalogWidget, canvasWidth: Int) -> Bool {
        guard let store, store.canEdit, let board = store.board else { return false }
        let instance = WidgetPlacer.newInstance(of: widget, on: board, canvasWidth: canvasWidth)
        store.update { $0.widgets.append(instance) }
        var next = placements
        next.insert(widget.name, on: board.surface)
        savePlacements(next)
        return true
    }

    func dismissPlacementsError() {
        placementsError = nil
    }

    func resetHome() throws {
        guard let store else { throw HomeBoardError.noConfiguration }
        guard try store.reset() else { throw HomeBoardError.noConfigurationFolder }
        var next = placements
        next.reset(store.surface)
        placements = next
        logSetAside(try placementsFile.save(next, surface: store.surface))
        placementsError = nil
    }

    private func logSetAside(_ broken: URL?) {
        guard let broken else { return }
        Self.log.error("widget placements file did not decode; moved it to \(broken.path, privacy: .public)")
    }

    func syncCatalogWaits() {
        let waits = store?.board?.widgets.contains { resolution(of: $0)?.waitsForCatalog == true } ?? false
        catalog.setWaitsForCatalog(waits, board: DefaultBoard.surface)
    }

    func runtimeJobs(isOnScreen: (BoardWidget) -> Bool = { _ in true }) -> [WidgetJob] {
        guard let board = store?.board else { return [] }
        return board.widgets.compactMap { widget in
            guard case let .ready(resolved)? = resolution(of: widget), resolved.source == nil else { return nil }
            return AppWidgetJobs.job(for: widget, resolved: resolved, isOnScreen: isOnScreen(widget))
        }
    }

    func sourceEntries(isOnScreen: (BoardWidget) -> Bool) -> [SourceWidgetEntry] {
        guard let board = store?.board else { return [] }
        return Self.sourceEntries(board: board, resolve: resolution(of:), isOnScreen: isOnScreen)
    }

    static func sourceEntries(
        board: Board, resolve: (BoardWidget) -> WidgetResolution?, isOnScreen: (BoardWidget) -> Bool
    ) -> [SourceWidgetEntry] {
        board.widgets.compactMap { widget in
            guard case let .ready(resolved)? = resolve(widget), let source = resolved.source else { return nil }
            return SourceWidgetEntry(id: widget.id, source: source, isVisible: isOnScreen(widget) && !widget.minimized)
        }
    }

    private func edit(_ id: String, _ change: (inout BoardWidget) -> Void) {
        store?.update { board in
            guard let index = board.widgets.firstIndex(where: { $0.id == id }) else { return }
            change(&board.widgets[index])
        }
    }

    private func savePlacements(_ next: WidgetPlacements) {
        placements = next
        do {
            logSetAside(try placementsFile.save(next, surface: DefaultBoard.surface))
            placementsError = nil
        } catch {
            Self.log.error("saving widget placements failed: \(error.localizedDescription, privacy: .public)")
            placementsError = error.localizedDescription
        }
    }
}
