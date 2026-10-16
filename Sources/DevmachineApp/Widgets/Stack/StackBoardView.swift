import AppKit
import SwiftUI
import DevmachineCore
import HarnessUsageKit

struct StackStyle {
    let indicators: ScrollIndicatorVisibility

    static var sidebar: StackStyle { StackStyle(indicators: .hidden) }
    static var contextSidebar: StackStyle { StackStyle(indicators: .automatic) }
}

/// The whole catalog, not just its release, for the reason `HomeJobsTrigger`
/// gives; the store's status, so a board that opens or turns valid places
/// the widgets that place themselves.
struct StackJobsTrigger: Equatable {
    let board: StackBoard
    let catalog: WidgetCatalog?
    let status: BoardStoreStatus?
}

/// Any stack surface: one scroll view of widget rows, an "Add widget" row
/// that shows while the pointer is over the panel, and the file's banner.
/// While a header drag is held the rows come from a frozen copy, so the
/// view holding the gesture is never moved or removed.
struct StackBoardView: View {
    static let space = "stack"
    static let cardInset: CGFloat = 14

    @ObservedObject private var controller: StackBoardController
    private let style: StackStyle
    private let isVisible: Bool
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var usage: HarnessUsageStore
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var prStore: PRStore
    @Environment(\.dmMetrics) private var m
    @State private var hovered: String?
    @State private var panelHovered = false
    @State private var showsGallery = false
    @State private var drag: StackDrag?
    @State private var choosing: WidgetChoiceRequest?
    @State private var editing: WidgetEditRequest?
    @State private var newWidget = NewWidgetHandoff()
    @State private var heights: [String: CGFloat] = [:]
    @State private var addRowHeight: CGFloat = 0
    @State private var bannerHeight: CGFloat = 0
    @State private var viewport: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var optionHeld = false
    @State private var flagsMonitor: Any?

    struct StackDrag: Equatable {
        let id: String
        let entries: [StackEntry]
        var translation: CGFloat
    }

    init(controller: StackBoardController, style: StackStyle, isVisible: Bool) {
        self.controller = controller
        self.style = style
        self.isVisible = isVisible
    }

    private var shown: [StackEntry] { drag?.entries ?? controller.board.entries }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bannerHeight = $0 }
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    row(entry, index: index)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[entry.id] = $0 }
                        .offset(y: drag?.id == entry.id ? drag?.translation ?? 0 : 0)
                        .zIndex(drag?.id == entry.id ? 1 : 0)
                }
                addRow
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { addRowHeight = $0 }
            }
            // Measured inside the scroll view: a row pinned to the scroll view's own width is wider than its
            // content area by the scroller, and a row that hugs its height then widens the panel on every pass.
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay(alignment: .topLeading) { dropLine }
            .coordinateSpace(name: Self.space)
            .overlayScrollers()
        }
        .scrollIndicators(style.indicators)
        .sheet(item: $choosing) { request in
            WidgetChoiceSheet(request: request, target: controller, onDone: { choosing = nil })
        }
        .sheet(item: $editing) { request in
            WidgetEditorSheet(request: request, target: controller, onDone: { editing = nil })
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
        .onHover { panelHovered = $0 }
        .onAppear {
            controller.runtime.providers = AppWidgetProviders(usage: usage, stats: stats, prs: prStore)
            controller.runtime.start()
            controller.setVisible(isVisible)
            watchOptionKey()
        }
        .onDisappear {
            if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
            flagsMonitor = nil
            optionHeld = false
            controller.runtime.stop()
            controller.setVisible(false)
            drag = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            readOptionKey()
        }
        .onChange(of: isVisible) { _, visible in
            controller.setVisible(visible)
            controller.runtime.setJobs(controller.runtimeJobs())
        }
        .onChange(
            of: StackJobsTrigger(board: controller.board, catalog: controller.catalog.catalog, status: controller.store?.status),
            initial: true
        ) { _, _ in
            controller.applyPlaces()
            controller.syncSources()
            controller.runtime.setJobs(controller.runtimeJobs())
        }
        .onChange(of: controller.board) { _, _ in
            if drag == nil { heights = heights.filter { id, _ in controller.board.index(of: id) != nil } }
        }
    }

    @ViewBuilder
    private func row(_ entry: StackEntry, index: Int) -> some View {
        let resolution = controller.resolution(of: entry)
        if case let .ready(resolved)? = resolution, let source = resolved.source {
            StackSourcesReader(sources: controller.sources) { sources in
                rowBody(entry, index: index, resolution: resolution, approval: WidgetApprovalDisplay.state(sources, entry.id, source))
            }
        } else {
            rowBody(entry, index: index, resolution: resolution, approval: nil)
        }
    }

    private func rowBody(_ entry: StackEntry, index: Int, resolution: WidgetResolution?, approval: ApprovalState?) -> some View {
        let rowModel = StackRowModel.make(
            entry: entry, index: index, count: shown.count, resolution: resolution, approval: approval,
            catalog: controller.catalog.catalog)
        let chrome = chrome(for: rowModel, entry: entry)
        return Group {
            if entry.collapsed {
                StackTitleHeader(title: rowModel.title)
            } else {
                switch rowModel.header {
                case .own:
                    content(entry, rowModel, resolution)
                case .bare:
                    content(entry, rowModel, resolution)
                        .overlay(alignment: .topTrailing) {
                            if rowModel.showsControls(
                                hovering: chrome.isHovered, optionHeld: optionHeld, dragging: chrome.isDragging,
                                canEdit: chrome.canEdit) {
                                StackHeaderControls()
                                    .padding(.horizontal, m.space.sm)
                                    .frame(height: m.control.small)
                                    .dmSurface(Color.dmBand, radius: DMRadius.pill)
                                    .fixedSize()
                                    .padding(.top, m.space.xs)
                                    .padding(.trailing, m.space.sm)
                            }
                        }
                case .standard:
                    VStack(alignment: .leading, spacing: 0) {
                        StackTitleHeader(title: rowModel.title)
                        content(entry, rowModel, resolution)
                    }
                }
            }
        }
        .environment(\.stackWidgetChrome, chrome)
        .environment(\.stackFillHeight, fillHeight(excluding: entry.id))
        .onHover { inside in
            if inside {
                hovered = entry.id
                readOptionKey()
            } else if hovered == entry.id {
                hovered = nil
            }
        }
    }

    @ViewBuilder
    private func content(_ entry: StackEntry, _ row: StackRowModel, _ resolution: WidgetResolution?) -> some View {
        let fixed: CGFloat? = if case let .fixed(points) = row.height { m.pt(points) } else { nil }
        let inset = m.pt(Self.cardInset)
        let size = CGSize(width: max(0, width - 2 * inset), height: fixed ?? m.pt(CGFloat(StackLayout.placeholderHeight())))
        let hugs = fixed == nil
        switch resolution {
        case let .ready(resolved)?:
            if let source = resolved.source {
                SourceWidgetCard(
                    id: entry.id, title: row.title, source: source, controller: controller.sources, size: size, hugs: hugs,
                    onOpenSession: model.openWidgetSession)
                    .frame(height: hugs ? nil : size.height)
                    .padding(.horizontal, inset)
            } else if let kind = StackAppViewKind(viewKind: resolved.viewKind) {
                StackAppWidgetView(
                    kind: kind, preceding: controller.expandedAppKinds(provider: resolved.provider, before: entry.id))
                    .frame(height: fixed)
            } else {
                AppWidgetView(resolved: resolved, size: size, hugs: hugs)
                    .frame(width: size.width, height: hugs ? nil : size.height)
                    .padding(.horizontal, inset)
            }
        case let .some(placeholder):
            WidgetPlaceholderView(
                icon: "puzzlepiece.extension", title: WidgetResolutionCopy.title(placeholder),
                detail: WidgetResolutionCopy.detail(placeholder, release: controller.catalog.catalog?.packagesRelease ?? ""))
                .frame(width: size.width, height: size.height)
                .padding(.horizontal, inset)
        case nil:
            Color.clear.frame(height: size.height)
        }
    }

    private func chrome(for row: StackRowModel, entry: StackEntry) -> StackWidgetChrome {
        StackWidgetChrome(
            model: row, isHovered: hovered == entry.id, isDragging: drag?.id == entry.id, isOptionHeld: optionHeld,
            isPanelHovered: panelHovered, canEdit: controller.canEdit, areaName: StackArea.name(controller.surface),
            onToggleCollapsed: { controller.setCollapsed(entry.id, !entry.collapsed) },
            onMoveUp: { controller.moveUp(entry.id) },
            onMoveDown: { controller.moveDown(entry.id) },
            onSize: { controller.setSize(entry.id, $0) },
            onRemove: { controller.remove(entry.id) },
            choices: controller.choices(for: entry.id),
            onChoose: { choice in choosing = WidgetChoiceRequest(entryID: entry.id, input: choice, title: row.title) },
            onEdit: controller.offersEdit(entry.id) ? { editing = .edit(entry.id) } : nil,
            onDragChanged: { translation in
                if drag == nil { drag = StackDrag(id: entry.id, entries: controller.board.entries, translation: 0) }
                drag?.translation = translation
            },
            onDragEnded: { endDrag() })
    }

    /// The local monitor hears nothing while another app is in front, so a
    /// ⌥ let go there is read again on return and on the next hover.
    private func readOptionKey() {
        let held = NSEvent.modifierFlags.contains(.option)
        if optionHeld != held { optionHeld = held }
    }

    private func watchOptionKey() {
        readOptionKey()
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            optionHeld = event.modifierFlags.contains(.option)
            return event
        }
    }

    private func endDrag() {
        guard let drag, let from = drag.entries.firstIndex(where: { $0.id == drag.id }) else { return }
        self.drag = nil
        let target = StackDragMath.targetIndex(
            from: from, translation: Double(drag.translation), heights: drag.entries.map { Double(heights[$0.id] ?? 0) })
        if let position = StackDropTarget.position(of: drag.id, to: target, in: drag.entries) {
            controller.move(drag.id, to: position)
        }
    }

    @ViewBuilder
    private var dropLine: some View {
        if let drag, let from = drag.entries.firstIndex(where: { $0.id == drag.id }) {
            let list = drag.entries.map { Double(heights[$0.id] ?? 0) }
            let target = StackDragMath.targetIndex(from: from, translation: Double(drag.translation), heights: list)
            if target != from {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: m.pt(2))
                    .offset(y: bannerHeight + CGFloat(StackDragMath.indicatorY(from: from, to: target, heights: list)))
                    .allowsHitTesting(false)
            }
        }
    }

    private func fillHeight(excluding id: String) -> CGFloat {
        let others = heights.filter { $0.key != id && controller.board.index(of: $0.key) != nil }.values.reduce(0, +)
        return max(0, viewport - others - addRowHeight - bannerHeight)
    }

    private var addRow: some View {
        let shows = (panelHovered || showsGallery) && controller.canEdit
        return DMButton("Add widget", systemImage: "plus", variant: .ghost, size: .small) { showsGallery = true }
            .padding(.horizontal, m.pt(10))
            .padding(.vertical, m.space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(shows ? 1 : 0)
            .allowsHitTesting(shows)
            .accessibilityHidden(!shows)
            .popover(isPresented: $showsGallery, arrowEdge: .trailing) {
                WidgetGalleryView(
                    surface: controller.surface, catalog: controller.catalog.catalog,
                    entries: controller.galleryEntries(), failure: galleryFailure,
                    blockedReason: { controller.addBlockedReason(for: $0) },
                    onAdd: { if controller.add($0) { showsGallery = false } },
                    onRetry: { controller.catalog.reloadSoon() },
                    templates: InlineWidgetTemplate.offered(on: WidgetContract.current.layout(of: controller.surface)),
                    canMakeWidgets: controller.canEdit,
                    onNewWidget: NewWidgetHandoff.chooser($newWidget, closing: $showsGallery))
                .opensNewWidget($newWidget, into: $editing)
            }
            .onChange(of: showsGallery) { _, open in if open { controller.catalog.reloadSoon() } }
    }

    private var galleryFailure: String? {
        if case let .failed(message) = controller.catalog.state { return message }
        return nil
    }

    @ViewBuilder
    private var banner: some View {
        if let problem = controller.problem {
            DMBanner(
                message: StackBoardCopy.invalid(
                    file: StackArea.fileName(controller.surface), problem: problem,
                    keepsLastGood: controller.store?.board != nil),
                lineLimit: 3
            ) {
                DMButton("Read again", variant: .ghost, size: .small) { controller.reload() }
            }
            .padding(.horizontal, m.pt(10))
            .padding(.vertical, m.space.sm)
        } else if let error = controller.writeError {
            DMBanner(
                message: StackBoardCopy.saveFailed(file: StackArea.fileName(controller.surface), error: error), lineLimit: 3
            ) {
                EmptyView()
            }
            .padding(.horizontal, m.pt(10))
            .padding(.vertical, m.space.sm)
        }
    }
}

/// Redraws a source row when its approval changes, so the row grows to fit
/// the approval card and shrinks back once allowed.
private struct StackSourcesReader<Content: View>: View {
    @ObservedObject var sources: WidgetSourceController
    @ViewBuilder let content: (WidgetSourceController) -> Content

    var body: some View { content(sources) }
}
