import SwiftUI
import AppKit
import DevmachineCore

enum WidgetChromeLayout {
    static let resizeCornerAlignment: Alignment = .bottomTrailing
    /// The grip and the ⋯ split the whole handle pill between them, its
    /// padding included, so no click on the glass falls between targets.
    static let gripArea = CGSize(width: 28, height: DMControlHeight.small)
    static let menuArea = CGSize(width: 24, height: DMControlHeight.small)
    static let resizeCorner = DMHitSize.regular
}

/// Where an overlay of a given size lands inside a card, so content
/// overlays can be checked against the chrome's hit areas.
enum WidgetOverlayPlacement {
    static func rect(of view: CGSize, at alignment: Alignment, in card: CGSize) -> CGRect {
        let x: CGFloat
        switch alignment.horizontal {
        case .leading: x = 0
        case .trailing: x = card.width - view.width
        default: x = (card.width - view.width) / 2
        }
        let y: CGFloat
        switch alignment.vertical {
        case .top: y = 0
        case .bottom: y = card.height - view.height
        default: y = (card.height - view.height) / 2
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: view)
    }
}

/// One widget on the canvas: its content, and on hover a small handle on
/// its top edge to drag it by, with the ⋯ menu, and a resize corner. The
/// handle sits on the edge so it never covers the card's own title or
/// buttons. Minimized, it is a pill.
struct WidgetChromeView: View {
    let widget: BoardWidget
    let resolution: WidgetResolution?
    let release: String
    let title: String
    let size: CGSize
    let editable: Bool
    let onMoveChanged: (CGSize) -> Void
    let onMoveEnded: () -> Void
    let onResizeChanged: (CGSize) -> Void
    let onResizeEnded: () -> Void
    let onFront: () -> Void
    let onPreset: (String) -> Void
    var onReset: () -> Void = {}
    let onMinimize: (Bool) -> Void
    let onRefresh: () -> Void
    let onRemove: () -> Void
    var onPillSize: (CGSize) -> Void = { _ in }
    var sources: WidgetSourceController?
    var onOpenSession: (WidgetTarget, String) -> Void = { _, _ in }
    var choices: [ChoiceInput] = []
    var onChoose: (ChoiceInput) -> Void = { _ in }
    var onEdit: (() -> Void)? = nil
    var onContentHeight: (CGFloat) -> Void = { _ in }

    @State private var hovering = false
    @State private var pillDragged = false
    /// Half of the handle sits outside the card, where the card's own hover
    /// ends, so the handle keeps itself shown while the pointer is on it.
    @State private var handleHovered = false
    /// A gesture lives only as long as its view: the handle and the corner
    /// stay while their drag is held, even when the pointer runs ahead of
    /// the card and its hover ends.
    @GestureState private var moving = false
    @GestureState private var resizing = false
    @Environment(\.dmMetrics) private var m

    var body: some View {
        Group {
            if widget.minimized {
                pill
            } else {
                card
            }
        }
        .onChange(of: moving) { _, held in if !held { onMoveEnded() } }
        .onChange(of: resizing) { _, held in if !held { onResizeEnded() } }
    }

    private var presets: [String] {
        guard case let .ready(resolved)? = resolution else { return [] }
        return (resolved.grows ? [BoardWidget.autoSize] : []) + WidgetContract.presetOrder.filter(resolved.widget.sizes.contains)
    }

    private var grows: Bool {
        if case let .ready(resolved)? = resolution { return resolved.grows }
        return false
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($moving) { _, held, _ in held = true }
            .onChanged { onMoveChanged($0.translation) }
            .onEnded { _ in onMoveEnded() }
    }

    /// Tap restores and drag moves, never both: a drag that ends over the
    /// pill must not also count as a click on it.
    private var pill: some View {
        Label {
            Text(verbatim: title)
        } icon: {
            Image(systemName: "rectangle.expand.vertical")
        }
        .font(.dm(11, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .padding(.vertical, m.space.sm)
        .padding(.horizontal, m.space.md)
        .dmGlass(radius: DMRadius.pill)
        .fixedSize()
        .contentShape(Capsule())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onPillSize($0) }
        .onTapGesture {
            guard !pillDragged else { return }
            onMinimize(false)
        }
        .gesture(pillMoveGesture, including: editable ? .all : .none)
        .help(Text(verbatim: "Restore \(title)"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: "Restore \(title)"))
        .accessibilityAction { onMinimize(false) }
    }

    private var pillMoveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($moving) { _, held, _ in held = true }
            .onChanged {
                pillDragged = true
                onMoveChanged($0.translation)
            }
            .onEnded { _ in
                onMoveEnded()
                DispatchQueue.main.async { pillDragged = false }
            }
    }

    private var card: some View {
        sizedContent
            .overlay {
                if hovering {
                    RoundedRectangle(cornerRadius: m.radius.card)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) { if (hovering || handleHovered || moving) && editable { handle } }
            .overlay(alignment: WidgetChromeLayout.resizeCornerAlignment) {
                if (hovering || resizing) && editable { resizeCorner }
            }
            .onHover { hovering = $0 }
            .simultaneousGesture(TapGesture().onEnded { onFront() })
    }

    /// A growing view on `auto` is drawn as tall as it is and tells the canvas
    /// how tall that is. With a height of its own it fills that box, and a
    /// copy no one sees measures what it would take unconstrained, so a drag
    /// past the content knows where the content ends.
    @ViewBuilder
    private var sizedContent: some View {
        if grows, widget.isAuto {
            content(hugs: true, size: size)
                .frame(width: size.width, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onContentHeight($0) }
                .frame(width: size.width, height: size.height, alignment: .top)
        } else if grows {
            content(hugs: false, size: size)
                .frame(width: size.width, height: size.height)
                .background(alignment: .topLeading) { naturalProbe }
        } else {
            content(hugs: false, size: size)
                .frame(width: size.width, height: size.height)
        }
    }

    private var naturalProbe: some View {
        content(hugs: true, size: CGSize(width: size.width, height: 0))
            .frame(width: size.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onContentHeight($0) }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(hugs: Bool, size: CGSize) -> some View {
        switch resolution {
        case let .ready(resolved)?:
            if let source = resolved.source, let sources {
                SourceWidgetCard(
                    id: widget.id, title: title, source: source, controller: sources, size: size, hugs: hugs,
                    onOpenSession: onOpenSession)
            } else {
                AppWidgetView(resolved: resolved, size: size, hugs: hugs)
            }
        case let .some(placeholder):
            WidgetPlaceholderView(
                icon: "puzzlepiece.extension", title: WidgetResolutionCopy.title(placeholder),
                detail: WidgetResolutionCopy.detail(placeholder, release: release))
        case nil:
            Color.clear
        }
    }

    private var handle: some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.dm(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: m.size(WidgetChromeLayout.gripArea).width, height: m.size(WidgetChromeLayout.gripArea).height)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .canvasCursor(.openHand)
                .accessibilityLabel(Text(verbatim: "Move \(title)"))
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.dm(10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: m.size(WidgetChromeLayout.menuArea).width, height: m.size(WidgetChromeLayout.menuArea).height)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text(verbatim: "Actions for \(title)"))
        }
        .dmGlass(radius: DMRadius.pill)
        .fixedSize()
        .onHover { handleHovered = $0 }
        .onDisappear { handleHovered = false }
        .offset(y: -m.control.small / 2)
    }

    @ViewBuilder
    private var menuItems: some View {
        if !presets.isEmpty {
            Picker("Size", selection: Binding(get: { widget.size }, set: { onPreset($0) })) {
                ForEach(presets, id: \.self) { preset in
                    Text(verbatim: sizeLabel(preset)).tag(preset)
                }
                if widget.size == BoardWidget.customSize {
                    Text(verbatim: "Custom").tag(BoardWidget.customSize)
                }
            }
            .pickerStyle(.inline)
        }
        Button("Reset size") { onReset() }.disabled(!editable)
        Button("Minimize") { onMinimize(true) }
        Button("Refresh") { onRefresh() }
        ForEach(choices) { choice in
            Button { onChoose(choice) } label: { Text(verbatim: choice.menuTitle) }
                .disabled(!editable)
        }
        if let onEdit {
            Button("Edit…") { onEdit() }.disabled(!editable)
        }
        Divider()
        Button("Remove from Home", role: .destructive) { onRemove() }
    }

    private func sizeLabel(_ preset: String) -> String {
        if preset == BoardWidget.autoSize { return "Auto" }
        guard let cells = WidgetContract.current.presetCells(preset) else { return preset }
        return "\(preset.prefix(1).uppercased() + preset.dropFirst()) · \(cells.columns)×\(cells.rows)"
    }

    private var resizeCorner: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.dm(9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: m.size(WidgetChromeLayout.resizeCorner).width, height: m.size(WidgetChromeLayout.resizeCorner).height)
            .contentShape(Rectangle())
            .canvasCursor(.crosshair)
            .onTapGesture(count: 2) { onReset() }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($resizing) { _, held, _ in held = true }
                    .onChanged { onResizeChanged($0.translation) }
                    .onEnded { _ in onResizeEnded() })
            .accessibilityLabel(Text(verbatim: "Resize \(title)"))
    }
}

/// Hover chrome appears and disappears under the pointer, and a view that
/// leaves while hovered never hears the exit, so the pushed cursor is
/// popped on disappear too.
private struct CanvasCursor: ViewModifier {
    let cursor: NSCursor
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, !pushed {
                    cursor.push()
                    pushed = true
                } else if !inside {
                    pop()
                }
            }
            .onDisappear { pop() }
    }

    private func pop() {
        guard pushed else { return }
        NSCursor.pop()
        pushed = false
    }
}

private extension View {
    func canvasCursor(_ cursor: NSCursor) -> some View {
        modifier(CanvasCursor(cursor: cursor))
    }
}
