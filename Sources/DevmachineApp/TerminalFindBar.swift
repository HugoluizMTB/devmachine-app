import SwiftUI

/// ⌘F over a pane: a bar that searches the session's own scrollback through
/// SwiftTerm and selects the match. Enter walks forward, ⇧Enter back, Esc
/// closes it and hands the keyboard back to the session.
struct TerminalFindBar: View {
    @EnvironmentObject var model: AppModel
    let kind: TerminalKind

    @State private var term = ""
    @State private var missed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.dmMuted)
            TextField("Find", text: $term)
                .textFieldStyle(.plain)
                .font(.dm(12))
                .foregroundStyle(missed ? Color.red.opacity(0.9) : Color.dmRowText)
                .frame(width: 180)
                .focused($focused)
                .onSubmit { step(forward: true) }
                .onChange(of: term) { _, _ in missed = false }
            stepButton("chevron.up", forward: false)
                .keyboardShortcut(.return, modifiers: .shift)
            stepButton("chevron.down", forward: true)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.dmMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.dmSidebarBg.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Color.dmDivider, lineWidth: 1))
        )
        .padding(12)
        .onAppear { focused = true }
    }

    private func stepButton(_ icon: String, forward: Bool) -> some View {
        Button { step(forward: forward) } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
