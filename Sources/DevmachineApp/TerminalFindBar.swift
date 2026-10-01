import SwiftUI

/// ⌘F over a pane: a bar that searches the session's own scrollback through
/// SwiftTerm and selects the match. Enter walks forward, ⇧Enter back, Esc
/// closes it and hands the keyboard back to the session.
struct TerminalFindBar: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var model: AppModel
    let kind: TerminalKind

    @State private var term = ""
    @State private var missed = false
    @FocusState private var focused: Bool

    var body: some View {
        DMSearchField(
            prompt: "Find", text: $term, focus: $focused, spacing: 6,
            textColor: missed ? Color.red.opacity(0.9) : Color.dmRowText, fieldWidth: 180
        ) {
            stepButton("chevron.up", forward: false)
                .keyboardShortcut(.return, modifiers: .shift)
            stepButton("chevron.down", forward: true)
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(DMIconButtonStyle(size: 10, weight: .semibold, hitSize: DMHitSize.regular))
            .keyboardShortcut(.escape, modifiers: [])
        }
        .onSubmit { step(forward: true) }
        .onChange(of: term) { _, _ in missed = false }
        .padding(.horizontal, m.space.md)
        .padding(.vertical, m.space.sm)
        .dmSurface(
            Color.dmSidebarBg.opacity(0.96), radius: DMRadius.tile, stroke: .dmDivider,
            lineWidth: 1)
        .padding(m.space.lg)
        .onAppear { focused = true }
    }

    private func stepButton(_ icon: String, forward: Bool) -> some View {
        DMIconButton(
            systemImage: icon, size: 10, weight: .semibold, tint: .dmRowText,
            hitSize: DMHitSize.regular
        ) { step(forward: forward) }
        .disabled(term.isEmpty)
    }

    private func step(forward: Bool) {
        missed = !TerminalRegistry.shared.find(term, in: kind, forward: forward)
    }

    private func close() {
        model.findTarget = nil
        TerminalRegistry.shared.endFind(in: kind)
    }
}

extension View {
    /// The bar sits over the pane, so it never changes the terminal's size —
    /// a resize would make the session rewrap its screen.
    func terminalFindBar(for kind: TerminalKind) -> some View {
        modifier(TerminalFindOverlay(kind: kind))
    }
}

private struct TerminalFindOverlay: ViewModifier {
    @EnvironmentObject var model: AppModel
    let kind: TerminalKind

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if model.findTarget == kind {
                TerminalFindBar(kind: kind)
                    .transition(.opacity)
            }
        }
    }
}
