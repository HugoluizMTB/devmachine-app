import Combine
import DevmachineCore
import Foundation
import os

/// What the menu bar title draws. It is its own object, so a change in the
/// popover never redraws the rasterised title.
@MainActor
final class MenubarLabelState: ObservableObject {
    @Published fileprivate(set) var items: [MenubarSlotItem] = [.brand]
}

struct MenubarApproval: Identifiable, Equatable {
    let id: String
    let title: String
    let source: ResolvedSource
}

/// The menu bar title and its popover, each a board. Title widgets run for
/// as long as the app does, window or not; popover widgets only while it is
/// open, and only the tab on screen.
@MainActor
final class MenubarController: ObservableObject {
    static let shared = MenubarController(
        slots: StackBoardController(surface: DefaultStackBoard.menubar),
        panel: StackBoardController(surface: DefaultStackBoard.menubarPanel))

    let slots: StackBoardController
    let panel: StackBoardController
    let label = MenubarLabelState()
    @Published private(set) var isPanelOpen = false
    @Published private(set) var approvals: [MenubarApproval] = []

    private var prs: PRStore?
    private var started = false
    private var refreshQueued = false
    private var triggers: [String: StackJobsTrigger] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var slotSourcesChange: AnyCancellable?
    private static let log = Logger(subsystem: "app.devmachine.mac", category: "widgets")

    init(slots: StackBoardController, panel: StackBoardController) {
        self.slots = slots
        self.panel = panel
    }

    func start(prs: PRStore, providers: AppWidgetProviders) {
        guard !started else { return }
        started = true
        self.prs = prs
        slots.runtime.providers = providers
        panel.runtime.providers = providers
        for board in [slots, panel] {
            board.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                    self?.queueRefresh()
                }
                .store(in: &cancellables)
        }
        prs.$openCount.removeDuplicates()
            .sink { [weak self] _ in self?.queueRefresh() }
            .store(in: &cancellables)
        panel.setVisibleEntries([])
        slots.start()
        panel.start()
        slots.setVisible(true)
        slots.runtime.start()
        refresh()
        Self.log.info("menubar widgets started")
    }

    func reload() {
        slots.reload()
        panel.reload()
    }

    func setPanelOpen(_ open: Bool) {
        guard open != isPanelOpen else { return }
        isPanelOpen = open
        if open {
            reloadSlotApprovals()
            panel.runtime.start()
        } else {
            panel.runtime.stop()
        }
        panel.setVisible(open)
        panel.runtime.setJobs(panel.runtimeJobs())
        Self.log.info("menubar panel \(open ? "opened" : "closed", privacy: .public)")
    }

    func showTab(_ id: String?) {
        panel.setVisibleEntries(id.map { [$0] } ?? [])
        panel.runtime.setJobs(panel.runtimeJobs())
    }

    private func waitingApprovals() -> [MenubarApproval] {
        guard slots.hasSources else { return [] }
        let catalog = slots.catalog.catalog
        return slots.board.entries.compactMap { entry in
            let resolution = slots.resolution(of: entry)
            guard case let .ready(resolved)? = resolution, let source = resolved.source else { return nil }
            switch WidgetApprovalDisplay.state(slots.sources, entry.id, source) {
            case .waiting, .denied:
                return MenubarApproval(
                    id: entry.id, title: MenubarTitles.title(entry, resolution: resolution, catalog: catalog), source: source)
            case .notNeeded, .allowed:
                return nil
            }
        }
    }

    /// Board, catalog or file status changed: place, sync and set jobs once
    /// per change, then redraw the title from what the slots show.
    func refresh() {
        for board in [slots, panel] {
            let trigger = StackJobsTrigger(board: board.board, catalog: board.catalog.catalog, status: board.store?.status)
            guard triggers[board.surface] != trigger else { continue }
            triggers[board.surface] = trigger
            board.applyPlaces()
            board.syncSources()
            board.runtime.setJobs(board.runtimeJobs())
        }
        watchSlotSources()
        let slots = self.slots
        let items = MenubarLabelModel.items(MenubarLabelInputs.make(
            board: slots.board, resolve: { slots.resolution(of: $0) }, openCount: prs?.openCount ?? 0,
            output: { id in slots.hasSources ? slots.sources.state(id).output : nil },
            approval: { id, source in
                slots.hasSources
                    ? WidgetApprovalDisplay.state(slots.sources, id, source)
                    : (source.needsApproval ? .waiting(hash: "") : .notNeeded)
            }))
        if items != label.items { label.items = items }
        let waiting = waitingApprovals()
        if waiting != approvals { approvals = waiting }
    }

    private func reloadSlotApprovals() {
        if slots.hasSources { slots.sources.reloadApprovals() }
    }

    private func queueRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshQueued = false
            refresh()
        }
    }

    private func watchSlotSources() {
        guard slotSourcesChange == nil, slots.hasSources else { return }
        slotSourcesChange = slots.sources.objectWillChange.sink { [weak self] _ in self?.queueRefresh() }
    }
}
