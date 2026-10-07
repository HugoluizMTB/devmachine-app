import SwiftUI
import AppKit
import DevmachineCore
import HarnessUsageKit

enum HomeCanvasMetrics {
    static let padding: CGFloat = 24
}

/// The whole catalog, not just its release: a local package edit can change
/// a widget's source within one release, and the old command must not keep running.
struct HomeJobsTrigger: Equatable {
    let board: Board?
    let catalog: WidgetCatalog?
    let visible: CGSize
}

struct HomeCanvasView: View {
    @ObservedObject var controller: HomeBoardController
    @ObservedObject private var catalog: WidgetCatalogStore
    @EnvironmentObject private var usage: HarnessUsageStore
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.dmMetrics) private var m
    @Environment(\.collapsedSidebarButtonFrame) private var sidebarButton
    @State private var showsGallery = false
    @State private var addButtonInWindow: CGRect?
    @State private var canvasSize: CGSize = .zero
    @State private var inWindow: CGRect = .zero
    @State private var clockRect: CGRect?

    init(controller: HomeBoardController) {
        self.controller = controller
        _catalog = ObservedObject(wrappedValue: controller.catalog)
    }

    var body: some View {
        let windowSpace = ContentView.windowSpace
        return GeometryReader { proxy in
            let size = CGSize(width: proxy.size.width, height: max(0, proxy.size.height - topInset))
            ZStack(alignment: .topLeading) {
                if let store = controller.store {
                    BoardCanvasLayer(
                        controller: controller, store: store, catalog: catalog, canvasSize: size, clockRect: $clockRect)
                        .offset(y: topInset)
                }
                catalogFailure
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .onAppear { canvasSize = proxy.size }
            .onChange(of: proxy.size) { _, next in canvasSize = next }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(windowSpace)) } action: {
                inWindow = $0
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WallpaperBackground(mapPlacement: mapPlacement))
        .clipped()
        .overlay(alignment: .topTrailing) { addButton }
        .onChange(of: showsGallery) { _, open in if open { catalog.reloadSoon() } }
        .onChange(of: model.pendingWidgetGallery, initial: true) { _, pending in
            guard pending else { return }
            model.pendingWidgetGallery = false
            showsGallery = true
        }
        .onAppear {
            controller.start()
            controller.runtime.providers = AppWidgetProviders(usage: usage, stats: stats)
            controller.runtime.start()
            controller.sources.start()
            stats.start()
        }
        .onDisappear {
            controller.runtime.stop()
            controller.sources.stop()
        }
    }

    private var addButton: some View {
        let windowSpace = ContentView.windowSpace
        return DMButton(icon: "plus", label: "Add a widget") { showsGallery = true }
            .dmGlass(radius: DMRadius.pill)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(windowSpace)) } action: {
                addButtonInWindow = $0
            }
            .padding(.top, m.space.md)
            .padding(.trailing, m.pt(HomeCanvasMetrics.padding))
            .popover(isPresented: $showsGallery, arrowEdge: .bottom) {
                WidgetGalleryPopover(
                    controller: controller, catalog: catalog,
                    canvasWidth: Int(canvasSize.width / m.pt(1)),
                    onAdded: { showsGallery = false })
            }
    }

    /// Moves the canvas down so neither floating button (the one that
    /// reopens the sidebar, and "+") covers a widget; the stored frames
    /// stay as they are, and every free spot lands below them.
    private var topInset: CGFloat {
        let local = { (rect: CGRect?) in rect?.offsetBy(dx: -inWindow.minX, dy: -inWindow.minY) }
        return [sidebarButton, addButtonInWindow].map {
            FloatingButtonClearance.topInset(button: local($0), contentMinX: 0, contentMinY: 0, gap: m.space.md)
        }.max() ?? 0
    }

    @ViewBuilder
    private var catalogFailure: some View {
        if catalog.catalog == nil, case let .failed(message) = catalog.state {
            DMErrorStateView(
                state: DMErrorState(title: "Could not fetch packages", message: message),
                retry: { catalog.reloadSoon() })
                .frame(width: m.card.sheet)
                .padding(m.space.lg)
                .dmGlass(radius: DMRadius.card)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func mapPlacement(_ size: NetworkMapSize) -> NetworkMapPlacement {
        guard canvasSize.width > 0 else { return .none }
        let padding = m.pt(HomeCanvasMetrics.padding)
        let clock = clockRect?.offsetBy(dx: 0, dy: topInset)
        switch size {
        case .large:
            return .filling(
                HomeMapArea.large(size: canvasSize, padding: padding, gap: padding, pillMinY: nil), keepClear: clock)
        case .compact:
            return .area(
                CGRect(origin: .zero, size: canvasSize).insetBy(dx: padding, dy: padding),
                centreX: clock.map { Double($0.midX) })
        }
    }
}

/// The gallery redraws when the board's state changes, so Add is
/// disabled (with the reason) while the board cannot be edited.
private struct WidgetGalleryPopover: View {
    @ObservedObject var controller: HomeBoardController
    @ObservedObject var catalog: WidgetCatalogStore
    let canvasWidth: Int
    let onAdded: () -> Void

    var body: some View {
        if let store = controller.store {
            BoardStoreReader(store: store) { gallery }
        } else {
            gallery
        }
    }

    private var gallery: some View {
        WidgetGalleryView(
            catalog: catalog.catalog,
            failure: failureMessage,
            blockedReason: controller.addBlockedReason,
            onAdd: { widget in if controller.add(widget, canvasWidth: canvasWidth) { onAdded() } },
            onRetry: { catalog.reloadSoon() })
    }

    private var failureMessage: String? {
        if case let .failed(message) = catalog.state { return message }
        return nil
    }
}

private struct BoardStoreReader<Content: View>: View {
    @ObservedObject var store: BoardStore
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}

private struct BoardCanvasLayer: View {
    @ObservedObject var controller: HomeBoardController
    @ObservedObject var store: BoardStore
    @ObservedObject var catalog: WidgetCatalogStore
    let canvasSize: CGSize
    @Binding var clockRect: CGRect?
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.harnessSettingsFacade) private var facade
    @Environment(\.dmMetrics) private var m
    @State private var drag: CanvasDrag?
    @State private var pillSizes: [String: CGSize] = [:]

    /// Before a pill has been drawn and measured, in points at 100%.
    private static let pillFallback = CGSize(width: 120, height: 28)

    struct CanvasDrag: Equatable {
        let id: String
        let start: BoardFrame
        var frame: BoardFrame
        var guides: [CanvasGuide]
    }

    private struct PlacesTrigger: Equatable {
        let release: String?
        let status: BoardStore.Status
        let harnesses: [String]
    }

    private var scale: Double { Double(m.pt(1)) }
    private var boardVisible: CGSize {
        CGSize(width: canvasSize.width / scale, height: canvasSize.height / scale)
    }
    private var enabledHarnesses: [String] {
        (settingsStore.settings ?? .empty).enabledHarnesses.map(\.rawValue).sorted()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let board = store.board {
                ForEach(board.widgets) { widget in
                    widgetView(widget, board: board)
                        .zIndex(CanvasLayout.stackLevel(of: widget, in: board, lifting: drag?.id))
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .overlay(alignment: .topLeading) { guides }
        .overlay(alignment: .top) { problemBanner }
        .onChange(
            of: PlacesTrigger(release: catalog.catalog?.packagesRelease, status: store.status, harnesses: enabledHarnesses),
            initial: true
        ) { _, _ in
            controller.applyPlaces(canvasWidth: Int(boardVisible.width), enabledHarnesses: Set(enabledHarnesses))
        }
        .onChange(
            of: HomeJobsTrigger(board: store.board, catalog: catalog.catalog, visible: boardVisible),
            initial: true
        ) { _, _ in
            controller.runtime.setJobs(controller.runtimeJobs(isOnScreen: isOnScreen))
            controller.sources.update(controller.sourceEntries(isOnScreen: isOnScreen))
        }
        .onChange(of: clockDisplayRect, initial: true) { _, rect in clockRect = rect }
        .onChange(of: store.board) { _, _ in drag = nil }
        .onDisappear { drag = nil }
    }

    /// Clamping pulls every widget back inside the canvas, so while the
    /// canvas has a size every widget is on screen; minimized ones are
    /// paused by their job instead.
    private func isOnScreen(_ widget: BoardWidget) -> Bool {
        boardVisible.width > 0 && boardVisible.height > 0
    }

    private func widgetView(_ widget: BoardWidget, board: Board) -> some View {
        let resolution = controller.resolution(of: widget)
        let current = drag.flatMap { $0.id == widget.id ? $0.frame : nil }
        let display = CanvasLayout.toDisplay((current ?? displayFrame(widget, resolution: resolution)).rect, scale: scale)
        return WidgetChromeView(
            widget: widget, resolution: resolution, release: catalog.catalog?.packagesRelease ?? "",
            title: title(widget, resolution), size: display.size, editable: store.canEdit,
            onMoveChanged: { moveChanged(widget, translation: $0, board: board) },
            onMoveEnded: { moveEnded(widget) },
            onResizeChanged: { resizeChanged(widget, translation: $0, resolution: resolution) },
            onResizeEnded: { resizeEnded(widget, resolution: resolution) },
            onFront: { controller.bringToFront(widget.id) },
            onPreset: { controller.setPreset(widget.id, preset: $0) },
            onMinimize: { controller.setMinimized(widget.id, $0) },
            onRefresh: { refresh(widget, resolution) },
            onRemove: { controller.remove(widget.id) },
            onPillSize: { pillSizes[widget.id] = $0 },
            sources: controller.sources,
            onOpenSession: openSession)
        .offset(x: display.minX, y: display.minY)
    }

    private func minimum(_ resolution: WidgetResolution?) -> CanvasSize {
        guard case let .ready(resolved)? = resolution else { return CanvasSize(w: 1, h: 1) }
        return resolved.minimum
    }

    private func sizes(_ resolution: WidgetResolution?) -> [String] {
        guard case let .ready(resolved)? = resolution else { return [] }
        return resolved.widget.sizes
    }

    /// Where a widget is drawn, in board points: grown to its minimum, or
    /// the pill's measured size when minimized, then pulled inside the canvas.
    /// Drags, guides and resizes start from this, never from the stored size.
    private func displayFrame(_ widget: BoardWidget, resolution: WidgetResolution?) -> BoardFrame {
        let size: CanvasSize
        if widget.minimized {
            let pill = pillSizes[widget.id].map { CanvasLayout.toBoard($0, scale: scale) } ?? Self.pillFallback
            size = CanvasSize(w: Int(pill.width.rounded(.up)), h: Int(pill.height.rounded(.up)))
        } else {
            let least = minimum(resolution)
            size = CanvasSize(w: max(widget.frame.w, least.w), h: max(widget.frame.h, least.h))
        }
        let rect = CanvasLayout.clamped(
            BoardFrame(x: widget.frame.x, y: widget.frame.y, w: size.w, h: size.h), in: boardVisible)
        return BoardFrame(x: Int(rect.minX.rounded()), y: Int(rect.minY.rounded()), w: size.w, h: size.h)
    }

    private func dragStart(_ widget: BoardWidget, resolution: WidgetResolution?) -> BoardFrame {
        if let drag, drag.id == widget.id { return drag.start }
        return displayFrame(widget, resolution: resolution)
    }

    private func moveChanged(_ widget: BoardWidget, translation: CGSize, board: Board) {
        guard store.canEdit else { return }
        let start = dragStart(widget, resolution: controller.resolution(of: widget))
        let delta = CanvasLayout.toBoard(translation, scale: scale)
        let others = board.widgets.filter { $0.id != widget.id }.map {
            displayFrame($0, resolution: controller.resolution(of: $0))
        }
        let move = CanvasLayout.moved(
            start, to: CGPoint(x: Double(start.x) + delta.width, y: Double(start.y) + delta.height), among: others)
        drag = CanvasDrag(id: widget.id, start: start, frame: move.frame, guides: move.guides)
    }

    /// A move keeps the stored size; only the place and the stacking change.
    private func moveEnded(_ widget: BoardWidget) {
        guard let drag, drag.id == widget.id else { return }
        self.drag = nil
        controller.move(widget.id, to: BoardFrame(x: drag.frame.x, y: drag.frame.y, w: widget.frame.w, h: widget.frame.h))
        controller.bringToFront(widget.id)
    }

    private func resizeChanged(_ widget: BoardWidget, translation: CGSize, resolution: WidgetResolution?) {
        guard store.canEdit else { return }
        let start = dragStart(widget, resolution: resolution)
        let delta = CanvasLayout.toBoard(translation, scale: scale)
        let frame = CanvasLayout.resized(
            start, width: Double(start.w) + delta.width, height: Double(start.h) + delta.height,
            minimum: minimum(resolution))
        drag = CanvasDrag(id: widget.id, start: start, frame: frame, guides: [])
    }

    private func resizeEnded(_ widget: BoardWidget, resolution: WidgetResolution?) {
        guard let drag, drag.id == widget.id else { return }
        self.drag = nil
        controller.resize(widget.id, to: drag.frame, sizes: sizes(resolution))
        controller.bringToFront(widget.id)
    }

    private func refresh(_ widget: BoardWidget, _ resolution: WidgetResolution?) {
        guard case let .ready(resolved)? = resolution else { return }
        if resolved.source != nil { return controller.sources.runNow(widget.id) }
        controller.runtime.refreshNow(WidgetRefreshKey(provider: resolved.provider, args: resolved.arguments))
    }

    private func openSession(_ target: WidgetTarget, _ session: String) {
        guard let item = SessionOpening.item(
            target: target, session: session, workspaces: model.visibleWorkspaces, localSessions: model.localSessions)
        else { return }
        switch item {
        case let .session(alias, name): model.clickSession(SessionRef(alias: alias, name: name))
        case .localSession: model.clickLocalSession(item)
        }
    }

    private func title(_ widget: BoardWidget, _ resolution: WidgetResolution?) -> String {
        if let inline = widget.inline { return inline.title }
        if case let .ready(resolved)? = resolution, resolved.viewKind == "app.harness-usage",
           let descriptor = facade.descriptor(for: HarnessID(rawValue: resolved.arguments["harness"] ?? "")) {
            return "\(descriptor.shortTitle) usage"
        }
        return WidgetTitle.make(type: widget.type, in: catalog.catalog)
    }

    private var clockDisplayRect: CGRect? {
        guard let board = store.board else { return nil }
        let clock = board.widgets.first { widget in
            guard !widget.minimized, case let .ready(resolved)? = controller.resolution(of: widget) else { return false }
            return resolved.viewKind == "app.clock"
        }
        return clock.map { CanvasLayout.toDisplay(displayFrame($0, resolution: nil).rect, scale: scale) }
    }

    @ViewBuilder
    private var guides: some View {
        if let drag {
            ForEach(Array(drag.guides.enumerated()), id: \.offset) { _, guide in
                switch guide.axis {
                case .vertical:
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: 1, height: (guide.end - guide.start) * scale)
                        .offset(x: guide.position * scale, y: guide.start * scale)
                case .horizontal:
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: (guide.end - guide.start) * scale, height: 1)
                        .offset(x: guide.start * scale, y: guide.position * scale)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var problemBanner: some View {
        VStack(spacing: m.space.sm) {
            boardProblem
            placementsWarning
        }
        .padding(.top, m.space.xl)
    }

    @ViewBuilder
    private var placementsWarning: some View {
        if let error = controller.placementsError {
            HStack(alignment: .top, spacing: m.space.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                Text(verbatim: HomeBoardCopy.placementsSaveFailed(error))
                    .font(.dm(11))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: m.space.sm)
                DMIconButton(systemImage: "xmark", size: 9, hitSize: DMHitSize.compact) {
                    controller.dismissPlacementsError()
                }
                .accessibilityLabel("Dismiss")
            }
            .frame(width: m.card.sheet, alignment: .leading)
            .padding(.horizontal, m.space.lg)
            .padding(.vertical, m.space.md)
            .dmGlass(radius: DMRadius.toast)
        }
    }

    @ViewBuilder
    private var boardProblem: some View {
        if case let .invalid(problem) = store.status {
            VStack(alignment: .leading, spacing: m.space.sm) {
                DMErrorStateView(
                    state: DMErrorState(
                        title: HomeBoardCopy.invalidTitle, cause: HomeBoardCopy.invalidCause(problem),
                        details: store.fileURL.path),
                    retry: { store.load() }, retryTitle: "Read again")
                Text(verbatim: HomeBoardCopy.invalidNote)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
            }
            .frame(width: m.card.sheet, alignment: .leading)
            .padding(m.space.lg)
            .dmGlass(radius: DMRadius.toast)
        } else if let error = store.writeError {
            DMErrorStateView(state: DMErrorState(title: "Could not save home.yml", message: error))
                .frame(width: m.card.sheet, alignment: .leading)
                .padding(m.space.lg)
                .dmGlass(radius: DMRadius.toast)
        }
    }
}
