import Combine
import DevmachineCore
import Foundation
import os

enum StackBoardError: LocalizedError, Equatable {
    case noConfiguration(surface: String)
    case noConfigurationFolder(surface: String)

    var errorDescription: String? {
        switch self {
        case let .noConfiguration(surface):
            "\(StackArea.sentenceName(surface)) has no layout file yet: "
                + "the devmachine CLI has not said where its configuration lives."
        case let .noConfigurationFolder(surface):
            "\(StackArea.sentenceName(surface)) was not reset: the devmachine configuration folder does not exist yet."
        }
    }
}

/// One sidebar's board: its file (or today's default in memory while there
/// is none), the catalog plus the built-in sidebar widgets, placements, and
/// the source widgets, which run only while the area is on screen.
@MainActor
final class StackBoardController: ObservableObject {
    static let sidebar = StackBoardController(surface: DefaultStackBoard.sidebar)
    static let contextSidebar = StackBoardController(surface: DefaultStackBoard.contextSidebar)

    static func startAll() {
        sidebar.start()
        contextSidebar.start()
    }

    static func reloadAll() {
        sidebar.reload()
        contextSidebar.reload()
    }

    @Published private(set) var store: StackBoardStore?
    @Published private(set) var placementsError: String?
    private(set) var isVisible = false
    private(set) var visibleEntries: Set<String>?
    let surface: String
    let catalog: WidgetCatalogStore
    let runtime = WidgetRuntimeDriver()

    private let placementsFile: WidgetPlacementsFile
    private var placements = WidgetPlacements()
    private var placementsLoaded = false
    private var context: [String: String] = [:]
    private var pendingContext: Set<String> = []
    private var watcher: BoardFileWatcher?
    private var watchedFolder: UInt64?
    private var configObserver: NSObjectProtocol?
    private var storeChange: AnyCancellable?
    private var catalogChange: AnyCancellable?
    private var started = false
    private var openingFromConfiguration = false
    private let configPath: @Sendable () async -> String?
    private var createdSources: WidgetSourceController?
    private static let log = Logger(subsystem: "app.devmachine.mac", category: "widgets")

    init(
        surface: String,
        placementsFile: WidgetPlacementsFile = WidgetPlacementsFile(fileURL: HomeBoardController.placementsURL()),
        catalog: WidgetCatalogStore = .shared,
        configPath: @escaping @Sendable () async -> String? = {
            await Task.detached { try? DevmachineCLI.resolve().configPath().path }.value
        },
        sources: WidgetSourceController? = nil
    ) {
        self.surface = surface
        self.placementsFile = placementsFile
        self.catalog = catalog
        self.configPath = configPath
        self.createdSources = sources
        catalogChange = catalog.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Created on first use, so a board without source widgets never reads
    /// the approvals file.
    var sources: WidgetSourceController {
        if let createdSources { return createdSources }
        let created = WidgetSourceController(runners: WidgetSourceLive.runners(), surface: surface, context: context)
        createdSources = created
        return created
    }

    var board: StackBoard { store?.board ?? DefaultStackBoard.make(surface: surface) }
    var canEdit: Bool { store?.canEdit ?? false }
    var writeError: String? { store?.writeError }
    var problem: BoardProblem? {
        if case let .invalid(problem)? = store?.status { return problem }
        return nil
    }

    func start() {
        guard !started else { return }
        started = true
        loadPlacements()
        if DemoMode.isActive {
            catalog.pin(DemoData.widgetCatalog)
            open(configDirectory: DemoMode.boardsFolder)
            return
        }
        catalog.reloadIfIdle()
        configObserver = NotificationCenter.default.addObserver(
            forName: ConfigDirectoryWatcher.changed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        openFromConfiguration()
    }

    /// Asks the CLI where its configuration lives; a reload asks again while
    /// no board is open, so a CLI installed after launch is picked up.
    private func openFromConfiguration() {
        guard store == nil, !openingFromConfiguration else { return }
        openingFromConfiguration = true
        Task {
            let path = await configPath()
            openingFromConfiguration = false
            if let path, store == nil { open(configDirectory: path) }
        }
    }

    func open(configDirectory: String) {
        let surface = self.surface
        let store = StackBoardStore(
            fileURL: BoardFiles.url(configDirectory: configDirectory, surface: surface), surface: surface,
            makeDefault: { DefaultStackBoard.make(surface: surface) })
        storeChange = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        watcher = nil
        watchedFolder = nil
        self.store = store
        store.load()
        watchIfNeeded(store)
    }

    /// Before `start()` nothing happens, so an early call never asks the CLI
    /// for its configuration or opens a real file in demo mode.
    func reload() {
        guard started else { return }
        reloadBoard()
    }

    private func reloadBoard() {
        guard let store else { return openFromConfiguration() }
        store.load()
        watchIfNeeded(store)
    }

    /// The watcher holds the `boards/` folder it opened, so once that folder
    /// is deleted it hears nothing more, even after a new one appears.
    private func watchIfNeeded(_ store: StackBoardStore) {
        let folder = Self.fileNumber(store.fileURL.deletingLastPathComponent())
        guard watcher == nil || folder != watchedFolder else { return }
        watchedFolder = folder
        watcher = folder == nil ? nil : BoardFileWatcher(fileURL: store.fileURL) { [weak self] in self?.reloadBoard() }
    }

    private static func fileNumber(_ url: URL) -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    func resolution(of entry: StackEntry) -> WidgetResolution? {
        StackResolution.resolve(entry, on: board, catalog: catalog.catalog)
    }

    func applyPlaces() {
        guard let store, store.canEdit, let current = store.board else { return }
        loadPlacements()
        let result = StackPlacer.place(on: current, catalog: catalog.catalog, placements: placements)
        if result.boardChanged { store.update { $0 = result.board } }
        if result.placementsChanged { savePlacements(result.placements) }
    }

    func galleryEntries() -> [CatalogWidget] { StackGallery.entries(catalog.catalog, surface: surface) }

    func addBlockedReason(for widget: CatalogWidget) -> String? {
        if !canEdit {
            return "\(StackArea.sentenceName(surface)) cannot change until "
                + "\(StackArea.fileName(surface)) can be read and written."
        }
        return StackGallery.blockedReason(for: widget, on: board)
    }

    @discardableResult
    func add(_ widget: CatalogWidget) -> Bool {
        guard addBlockedReason(for: widget) == nil, let store else { return false }
        store.update { _ = $0.insert(StackPlacer.newEntry(of: widget, on: $0), at: .end) }
        loadPlacements()
        var next = placements
        next.insert(widget.name, on: surface)
        savePlacements(next)
        return true
    }

    func moveUp(_ id: String) { edit { $0.moveUp(id) } }
    func moveDown(_ id: String) { edit { $0.moveDown(id) } }
    func move(_ id: String, toIndex index: Int) { edit { $0.move(id, toIndex: index) } }
    func move(_ id: String, to position: StackPosition) { edit { $0.move(id, to: position) } }
    func setCollapsed(_ id: String, _ collapsed: Bool) { edit { $0.setCollapsed(id, collapsed) } }
    func setSize(_ id: String, _ size: StackSize?) { edit { $0.setSize(id, size) } }
    func remove(_ id: String) { edit { $0.remove(id) } }

    func reset() throws {
        guard let store else { throw StackBoardError.noConfiguration(surface: surface) }
        guard try store.reset() else { throw StackBoardError.noConfigurationFolder(surface: surface) }
        loadPlacements()
        var next = placements
        next.reset(surface)
        placements = next
        logSetAside(try placementsFile.save(next, surface: surface))
        placementsError = nil
    }

    /// `pending` names keys still being read (repo and branch while the git
    /// probe is out); widgets that read them wait, the others run at once.
    func setContext(_ next: [String: String], pending: Set<String> = []) {
        context = next
        pendingContext = pending
        createdSources?.setContext(next, pending: pending)
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if !visible { createdSources?.stop() }
        syncSources()
    }

    /// The popover shows one tab at a time; nil means every entry is on screen.
    func setVisibleEntries(_ ids: Set<String>?) {
        guard ids != visibleEntries else { return }
        visibleEntries = ids
        syncSources()
    }

    var hasSources: Bool { createdSources != nil }

    private func isOnScreen(_ entry: StackEntry) -> Bool {
        isVisible && !entry.collapsed && (visibleEntries?.contains(entry.id) ?? true)
    }

    /// Called whenever the board, the catalog or the visibility changes.
    func syncSources() {
        catalog.setWaitsForCatalog(
            board.entries.contains { resolution(of: $0)?.waitsForCatalog == true }, board: surface)
        let entries = board.entries.compactMap { entry -> SourceWidgetEntry? in
            guard case let .ready(resolved)? = resolution(of: entry), let source = resolved.source else { return nil }
            return SourceWidgetEntry(id: entry.id, source: source, isVisible: isOnScreen(entry))
        }
        guard !entries.isEmpty || createdSources != nil else { return }
        sources.setContext(context, pending: pendingContext)
        sources.update(entries)
        if isVisible { sources.start() }
    }

    func runtimeJobs() -> [WidgetJob] {
        board.entries.compactMap { entry in
            guard case let .ready(resolved)? = resolution(of: entry), resolved.source == nil,
                  !AppStackWidgets.viewKinds.contains(resolved.viewKind),
                  !AppMenubarWidgets.viewKinds.contains(resolved.viewKind)
            else { return nil }
            return AppWidgetJobs.job(for: entry.boardWidget, resolved: resolved, isOnScreen: isOnScreen(entry))
        }
    }

    /// The first expanded entry drawn by `provider`; for session context it
    /// shows the loading state and the age label, as the panel did once.
    func leadEntryID(provider: String) -> String? {
        board.entries.first { entry in
            guard !entry.collapsed, case let .ready(resolved)? = resolution(of: entry) else { return false }
            return resolved.provider == provider
        }?.id
    }

    /// The expanded app views `provider` draws above `id`, so a section
    /// knows whether it leads once it sees what the others have to show.
    func expandedAppKinds(provider: String, before id: String) -> [StackAppViewKind] {
        guard let index = board.index(of: id) else { return [] }
        return board.entries.prefix(index).compactMap { entry in
            guard !entry.collapsed, case let .ready(resolved)? = resolution(of: entry), resolved.provider == provider
            else { return nil }
            return StackAppViewKind(viewKind: resolved.viewKind)
        }
    }

    /// `path` and `harness` come from the session-context poll too, so a
    /// widget reading them keeps it running.
    var needsSessionContext: Bool {
        leadEntryID(provider: "app/session-context") != nil || expandedSourceReads(["path", "harness"])
    }

    var needsGitContext: Bool { expandedSourceReads(["repo", "branch"]) }

    private func expandedSourceReads(_ keys: [String]) -> Bool {
        board.entries.contains { entry in
            guard !entry.collapsed, case let .ready(resolved)? = resolution(of: entry), let source = resolved.source
            else { return false }
            return keys.contains { source.reads(contextKey: $0) }
        }
    }

    private func edit(_ change: (inout StackBoard) -> Bool) {
        guard let store, store.canEdit else { return }
        store.update { board in _ = change(&board) }
    }

    private func loadPlacements() {
        guard !placementsLoaded else { return }
        placementsLoaded = true
        placements = placementsFile.load()
    }

    private func savePlacements(_ next: WidgetPlacements) {
        placements = next
        do {
            logSetAside(try placementsFile.save(next, surface: surface))
            placementsError = nil
        } catch {
            Self.log.error("saving widget placements failed: \(error.localizedDescription, privacy: .public)")
            placementsError = error.localizedDescription
        }
    }

    private func logSetAside(_ broken: URL?) {
        guard let broken else { return }
        Self.log.error("widget placements file did not decode; moved it to \(broken.path, privacy: .public)")
    }
}

extension StackBoardController: WidgetEditTarget {
    var editSurface: String { surface }
    var editFileName: String { StackArea.fileName(surface) }
    var editCatalog: WidgetCatalog? { StackCatalog.merged(catalog.catalog) }

    func editableEntry(_ id: String) -> EditableEntry? {
        board.entries.first { $0.id == id }.map(EditableEntry.init)
    }

    func problem(with edit: EntryEdit, for id: String) -> String? {
        guard let index = board.index(of: id) else { return nil }
        let old = board.entries[index]
        var entry = old
        guard edit.apply(to: &entry), !entry.isInline else { return nil }
        let merged = StackCatalog.merged(catalog.catalog)
        let reason = { (entry: StackEntry) -> String? in
            if case let .refused(_, reason) = WidgetResolution.resolve(entry.boardWidget, in: merged) { return reason }
            return nil
        }
        let after = edit.undeclaredInput(for: entry.boardWidget, in: merged) ?? reason(entry)
        return after == reason(old) ? nil : after
    }

    @discardableResult
    func apply(_ edit: EntryEdit, to id: String) -> Bool {
        guard problem(with: edit, for: id) == nil else { return false }
        guard let store, store.canEdit, let index = board.index(of: id) else { return false }
        var entry = board.entries[index]
        guard edit.apply(to: &entry) else { return false }
        store.update { $0.entries[index] = entry }
        return true
    }

    func addInline(_ inline: InlineWidget, title: String, preset: String) -> String? {
        guard let store, store.canEdit, !StackGallery.isFull(board) else { return nil }
        let id = board.uniqueID(base: title)
        store.update { _ = $0.insert(StackEntry(id: id, type: "", inline: inline), at: .end) }
        return id
    }
}
