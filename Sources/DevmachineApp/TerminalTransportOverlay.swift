import SwiftUI
import DevmachineCore

extension View {
    /// The note a remote pane shows when mosh could not get through and ssh
    /// took over. It sits over the terminal, so the session is never resized.
    func terminalTransport(for kind: TerminalKind) -> some View {
        modifier(TerminalTransportNotice(kind: kind))
    }
}

private struct TerminalTransportNotice: ViewModifier {
    @Environment(\.dmMetrics) private var m
    @ObservedObject private var store = RemoteTransportStore.shared
    let kind: TerminalKind
    @State private var showsDetails = false

    static let visibleFor: Duration = .seconds(20)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if let pane = store.panes[kind], pane.showsNotice, let reason = pane.reason {
                    notice(pane, reason: reason)
                        .padding(m.pt(10))
                        .transition(.opacity)
                        .task(id: pane) {
                            try? await Task.sleep(for: Self.visibleFor)
                            if !showsDetails { store.dismissNotice(kind) }
                        }
                }
            }
            .animation(.easeOut(duration: 0.15), value: store.panes[kind]?.showsNotice)
    }

    private func notice(_ pane: RemoteTransportStore.Pane, reason: MoshFallbackReason) -> some View {
        HStack(spacing: m.space.sm) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(Color.dmMuted)
                .accessibilityHidden(true)
            Text(verbatim: reason.notice(machine: pane.machine))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: "\u{00B7}")
                .foregroundStyle(Color.dmMuted)
                .accessibilityHidden(true)
            DMButton("Details", variant: .link, size: .small) { showsDetails = true }
                .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                    if let state = pane.errorState {
                        DMErrorStateView(state: state, retry: {
                            showsDetails = false
                            store.retry(kind)
                        }, retryTitle: "Try mosh again")
                        .padding(m.pt(18))
                        .frame(width: m.pt(400))
                    }
                }
            DMButton(icon: "xmark", label: "Dismiss", size: .small) { store.dismissNotice(kind) }
        }
        .font(.dm(11))
        .padding(.leading, m.pt(10))
        .padding(.trailing, m.space.xs)
        .padding(.vertical, m.pt(3))
        .dmGlass(radius: DMRadius.pill)
    }
}

/// "mosh" or "ssh", for a pane header. Nothing while the pane is still
/// connecting, and nothing for a pane on this Mac.
struct TerminalTransportBadge: View {
    @ObservedObject private var store = RemoteTransportStore.shared
    let kind: TerminalKind

    var body: some View {
        if let pane = store.panes[kind], let transport = pane.transport {
            DMPill(text: transport.rawValue, color: transport == .mosh ? .green : Color.dmMuted)
                .help(Text(verbatim: pane.badgeHelp))
                .accessibilityLabel(Text(verbatim: pane.badgeHelp))
        }
    }
}
