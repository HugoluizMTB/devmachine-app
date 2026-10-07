import SwiftUI
import AppKit
import DevmachineCore

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
    let onMinimize: (Bool) -> Void
    let onRefresh: () -> Void
    let onRemove: () -> Void
    var onPillSize: (CGSize) -> Void = { _ in }

    @State private var hovering = false
    @State private var pillDragged = false
    /// Half of the handle sits outside the card, where the card's own hover
    /// ends, so the handle keeps itself shown while the pointer is on it.
    @State private var handleHovered = false
    @Environment(\.dmMetrics) private var m

    var body: some View {
        if widget.minimized {
            pill
        } else {
            card
        }
    }

    private var presets: [String] {
        guard case let .ready(resolved)? = resolution else { return [] }
        return WidgetContract.presetOrder.filter(resolved.widget.sizes.contains)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
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
        content
            .frame(width: size.width, height: size.height)
            .overlay {
                if hovering {
                    RoundedRectangle(cornerRadius: m.radius.card)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) { if (hovering || handleHovered) && editable { handle } }
            .overlay(alignment: .bottomTrailing) { if hovering && editable { resizeCorner } }
            .onHover { hovering = $0 }
            .simultaneousGesture(TapGesture().onEnded { onFront() })
    }

    @ViewBuilder
    private var content: some View {
        switch resolution {
        case let .ready(resolved)?:
            AppWidgetView(resolved: resolved, size: size)
        case let .some(placeholder):
            WidgetPlaceholderView(
                icon: "puzzlepiece.extension", title: WidgetResolutionCopy.title(placeholder),
                detail: WidgetResolutionCopy.detail(placeholder, release: release))
        case nil:
            Color.clear
        }
    }

    private var handle: some View {
        HStack(spacing: m.space.xs) {
            Image(systemName: "line.3.horizontal")
                .font(.dm(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: m.size(DMHitSize.compact).width, height: m.size(DMHitSize.compact).height)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .canvasCursor(.openHand)
                .accessibilityLabel(Text(verbatim: "Move \(title)"))
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text(verbatim: "Actions for \(title)"))
        }
        .padding(.horizontal, m.space.sm)
        .frame(height: m.control.small)
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
        Button("Minimize") { onMinimize(true) }
        Button("Refresh") { onRefresh() }
        Divider()
        Button("Remove from Home", role: .destructive) { onRemove() }
    }

    private func sizeLabel(_ preset: String) -> String {
        guard let cells = WidgetContract.engine10.presetCells(preset) else { return preset }
        return "\(preset.prefix(1).uppercased() + preset.dropFirst()) · \(cells.columns)×\(cells.rows)"
    }

    private var resizeCorner: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.dm(9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: m.size(DMHitSize.compact).width, height: m.size(DMHitSize.compact).height)
            .contentShape(Rectangle())
            .canvasCursor(.crosshair)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
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
