import SwiftUI
import DevmachineCore

/// What a stack row hands its header: the row's model and its actions.
struct StackWidgetChrome {
    let model: StackRowModel
    let isHovered: Bool
    let isDragging: Bool
    let isOptionHeld: Bool
    let isPanelHovered: Bool
    let canEdit: Bool
    let areaName: String
    let onToggleCollapsed: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSize: (StackSize) -> Void
    let onRemove: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
}

private struct StackWidgetChromeKey: EnvironmentKey {
    static var defaultValue: StackWidgetChrome? { nil }
}

private struct StackFillHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var stackWidgetChrome: StackWidgetChrome? {
        get { self[StackWidgetChromeKey.self] }
        set { self[StackWidgetChromeKey.self] = newValue }
    }

    /// The panel height left for this row once every other row is drawn.
    var stackFillHeight: CGFloat {
        get { self[StackFillHeightKey.self] }
        set { self[StackFillHeightKey.self] = newValue }
    }
}

/// Grip, chevron and ⋯ for a stack widget. Outside a stack it draws
/// nothing, so the moved sections look as before wherever else they appear.
/// The grip's gesture lives in this view, so the controls stay while their
/// drag is held even after the pointer leaves the row.
struct StackHeaderControls: View {
    var alwaysShown = false
    @Environment(\.stackWidgetChrome) private var chrome
    @Environment(\.dmMetrics) private var m
    @GestureState private var dragging = false

    var body: some View {
        Group {
            if let chrome, chrome.model.showsControls(
                hovering: chrome.isHovered, optionHeld: chrome.isOptionHeld, dragging: chrome.isDragging || dragging,
                canEdit: chrome.canEdit, inTitleHeader: alwaysShown
            ) {
                HStack(spacing: m.space.xxs) {
                    grip(chrome)
                    DMIconButton(
                        systemImage: chrome.model.isCollapsed ? "chevron.right" : "chevron.down", size: 10,
                        hitSize: DMHitSize.compact
                    ) { chrome.onToggleCollapsed() }
                    .help(chrome.model.isCollapsed ? "Expand" : "Collapse")
                    Menu {
                        StackWidgetMenu(chrome: chrome)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(Text(verbatim: "Actions for \(chrome.model.title)"))
                }
            }
        }
        .onChange(of: dragging) { _, held in if !held { chrome?.onDragEnded() } }
    }

    private func grip(_ chrome: StackWidgetChrome) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.dm(10, weight: .semibold))
            .foregroundStyle(Color.dmMuted)
            .frame(width: m.size(DMHitSize.compact).width, height: m.size(DMHitSize.compact).height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(StackBoardView.space))
                    .updating($dragging) { _, held, _ in held = true }
                    .onChanged { chrome.onDragChanged($0.translation.height) }
                    .onEnded { _ in chrome.onDragEnded() })
            .accessibilityLabel(Text(verbatim: "Move \(chrome.model.title)"))
    }
}

private struct StackWidgetMenu: View {
    let chrome: StackWidgetChrome

    var body: some View {
        Button("Move up") { chrome.onMoveUp() }.disabled(!chrome.model.canMoveUp)
        Button("Move down") { chrome.onMoveDown() }.disabled(!chrome.model.canMoveDown)
        if chrome.model.sizeChoices.count > 1 {
            Picker("Size", selection: Binding(
                get: { chrome.model.size ?? chrome.model.sizeChoices[0] },
                set: { if $0 != chrome.model.size { chrome.onSize($0) } }
            )) {
                ForEach(chrome.model.sizeChoices, id: \.self) { size in
                    Text(verbatim: StackWidgetMenuText.label(size)).tag(size)
                }
            }
            .pickerStyle(.inline)
        }
        Divider()
        Button(role: .destructive) { chrome.onRemove() } label: {
            Text(verbatim: "Remove from \(chrome.areaName)")
        }
    }
}

/// The header a collapsed widget, or a widget without its own title row,
/// shows: the section label of the context panel, with the controls.
struct StackTitleHeader: View {
    let title: String

    var body: some View {
        DMSection(
            padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
            label: { DMSectionLabel(text: title.uppercased()) },
            trailing: { StackHeaderControls(alwaysShown: true) })
    }
}

/// The title row of an app widget that has nothing to show; it draws only
/// while `StackRowModel.showsEmptyHeader` says so, with the controls its
/// row style gives.
struct StackEmptyWidgetHeader: View {
    @Environment(\.stackWidgetChrome) private var chrome

    var body: some View {
        if let chrome, StackRowModel.showsEmptyHeader(
            panelHovered: chrome.isPanelHovered, dragging: chrome.isDragging, canEdit: chrome.canEdit) {
            DMSection(
                padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
                label: { DMSectionLabel(text: chrome.model.title.uppercased()) },
                trailing: { StackHeaderControls() })
        }
    }
}
