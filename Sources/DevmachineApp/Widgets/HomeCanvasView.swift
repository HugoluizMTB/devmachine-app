import SwiftUI
import AppKit
import DevmachineCore
import HarnessUsageKit

enum HomeCanvasMetrics {
    static let padding: CGFloat = 24
}

struct HomeCanvasView: View {
    @ObservedObject var controller: HomeBoardController
    @ObservedObject private var catalog: WidgetCatalogStore
    @EnvironmentObject private var usage: HarnessUsageStore
    @EnvironmentObject private var stats: StatsStore
    @Environment(\.dmMetrics) private var m
    @Environment(\.collapsedSidebarButtonFrame) private var sidebarButton
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
        .onAppear {
            controller.start()
            controller.runtime.providers = AppWidgetProviders(usage: usage, stats: stats)
            controller.runtime.start()
            stats.start()
        }
        .onDisappear { controller.runtime.stop() }
    }

    /// Moves the canvas down so the floating button that reopens the
    /// sidebar covers no widget; the stored frames stay as they are.
    private var topInset: CGFloat {
        let button = sidebarButton?.offsetBy(dx: -inWindow.minX, dy: -inWindow.minY)
        return FloatingButtonClearance.topInset(button: button, contentMinX: 0, contentMinY: 0, gap: m.space.md)
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

private struct BoardCanvasLayer: View {
    @ObservedObject var controller: HomeBoardController
    @ObservedObject var store: BoardStore
    @ObservedObject var catalog: WidgetCatalogStore
    let canvasSize: CGSize
    @Binding var clockRect: CGRect?
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.harnessSettingsFacade) private var facade
    @Environment(\.dmMetrics) private var m
    @State private var drag: CanvasDrag?

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

    private struct JobsTrigger: Equatable {
        let board: Board?
        let release: String?
        let visible: CGSize
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
                ForEach(board.widgets.sorted { $0.z < $1.z }) { widget in
                    widgetView(widget, board: board)
                }
            }
            guides
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .overlay(alignment: .top) { problemBanner }
        .onChange(
            of: PlacesTrigger(release: catalog.catalog?.packagesRelease, status: store.status, harnesses: enabledHarnesses),
            initial: true
        ) { _, _ in
            controller.applyPlaces(canvasWidth: Int(boardVisible.width), enabledHarnesses: Set(enabledHarnesses))
        }
        .onChange(
            of: JobsTrigger(board: store.board, release: catalog.catalog?.packagesRelease, visible: boardVisible),
            initial: true
        ) { _, _ in
            controller.runtime.setJobs(controller.runtimeJobs(isOnScreen: isOnScreen))
        }
        .onChange(of: clockDisplayRect, initial: true) { _, rect in clockRect = rect }
    }

    private func isOnScreen(_ widget: BoardWidget) -> Bool {
        guard boardVisible.width > 0, boardVisible.height > 0 else { return false }
        let rect = CanvasLayout.clamped(widget.frame, in: boardVisible)
        return rect.intersects(CGRect(origin: .zero, size: boardVisible))
    }

    private func widgetView(_ widget: BoardWidget, board: Board) -> some View {
        let resolution = controller.resolution(of: widget)
        let current = drag.flatMap { $0.id == widget.id ? $0.frame : nil }
        let display = displayRect(current ?? widget.frame, minimum: minimum(resolution), clamp: current == nil)
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
            onRefresh: { refresh(resolution) },
            onRemove: { controller.remove(widget.id) })
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

    private func displayRect(_ frame: BoardFrame, minimum: CanvasSize, clamp: Bool) -> CGRect {
        let grown = BoardFrame(x: frame.x, y: frame.y, w: max(frame.w, minimum.w), h: max(frame.h, minimum.h))
        let rect = clamp ? CanvasLayout.clamped(grown, in: boardVisible) : grown.rect
        return CanvasLayout.toDisplay(rect, scale: scale)
    }

    private func clampedFrame(_ widget: BoardWidget) -> BoardFrame {
        let rect = CanvasLayout.clamped(widget.frame, in: boardVisible)
        return BoardFrame(x: Int(rect.minX.rounded()), y: Int(rect.minY.rounded()), w: widget.frame.w, h: widget.frame.h)
    }

    private func dragStart(_ widget: BoardWidget) -> BoardFrame {
        if let drag, drag.id == widget.id { return drag.start }
        controller.bringToFront(widget.id)
        return clampedFrame(widget)
    }

    private func moveChanged(_ widget: BoardWidget, translation: CGSize, board: Board) {
        guard store.canEdit else { return }
        let start = dragStart(widget)
        let delta = CanvasLayout.toBoard(translation, scale: scale)
        let others = board.widgets.filter { $0.id != widget.id && !$0.minimized }.map(clampedFrame)
        let move = CanvasLayout.moved(
            start, to: CGPoint(x: Double(start.x) + delta.width, y: Double(start.y) + delta.height), among: others)
        drag = CanvasDrag(id: widget.id, start: start, frame: move.frame, guides: move.guides)
    }

    private func moveEnded(_ widget: BoardWidget) {
        guard let drag, drag.id == widget.id else { return }
        controller.move(widget.id, to: drag.frame)
        self.drag = nil
    }

    private func resizeChanged(_ widget: BoardWidget, translation: CGSize, resolution: WidgetResolution?) {
        guard store.canEdit else { return }
        let start = dragStart(widget)
        let delta = CanvasLayout.toBoard(translation, scale: scale)
        let frame = CanvasLayout.resized(
            start, width: Double(start.w) + delta.width, height: Double(start.h) + delta.height,
            minimum: minimum(resolution))
        drag = CanvasDrag(id: widget.id, start: start, frame: frame, guides: [])
    }

    private func resizeEnded(_ widget: BoardWidget, resolution: WidgetResolution?) {
        guard let drag, drag.id == widget.id else { return }
        controller.resize(widget.id, to: drag.frame, sizes: sizes(resolution))
        self.drag = nil
    }

    private func refresh(_ resolution: WidgetResolution?) {
        guard case let .ready(resolved)? = resolution else { return }
        controller.runtime.refreshNow(WidgetRefreshKey(provider: resolved.provider, args: resolved.arguments))
    }

    private func title(_ widget: BoardWidget, _ resolution: WidgetResolution?) -> String {
        if case let .ready(resolved)? = resolution, resolved.viewKind == "app.harness-usage",
           let descriptor = facade.descriptor(for: HarnessID(rawValue: resolved.arguments["harness"] ?? "")) {
            return "\(descriptor.shortTitle) usage"
        }
        return WidgetTitle.make(type: widget.type)
    }

    private var clockDisplayRect: CGRect? {
        guard let board = store.board else { return nil }
        let clock = board.widgets.first { widget in
            guard !widget.minimized, case let .ready(resolved)? = controller.resolution(of: widget) else { return false }
            return resolved.viewKind == "app.clock"
        }
        return clock.map { displayRect($0.frame, minimum: CanvasSize(w: 1, h: 1), clamp: true) }
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

    @ViewBuilder
    private var problemBanner: some View {
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
            .padding(.top, m.space.xl)
        } else if let error = store.writeError {
            DMErrorStateView(state: DMErrorState(title: "Could not save home.yml", message: error))
                .frame(width: m.card.sheet, alignment: .leading)
                .padding(m.space.lg)
                .dmGlass(radius: DMRadius.toast)
                .padding(.top, m.space.xl)
        }
    }
}
