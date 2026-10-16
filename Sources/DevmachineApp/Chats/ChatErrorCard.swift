import SwiftUI
import DevmachineCore

/// The failure of a turn, inside the conversation: what happened in plain
/// words, the way on, and the CLI's own message under Show details.
struct ChatErrorCard: View {
    let failure: ChatFailure
    let chatID: String
    let harness: HarnessID
    let place: ChatPlace
    var compact = false
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var store = ChatStore.shared
    @Environment(\.dmMetrics) private var m
    @Environment(\.dmOpenCLIUpdate) private var openCLIUpdate
    @State private var showsDetails = false

    private var presentation: ChatFailurePresentation {
        ChatFailurePresentation(failure: failure, harness: harness, place: place)
    }

    private var tint: Color { presentation.tone == .warning ? .orange : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(compact ? 8 : 12)) {
            HStack(spacing: m.pt(8)) {
                Image(systemName: presentation.symbol)
                    .font(.dm(compact ? 12 : 16))
                    .foregroundStyle(tint)
                Text(verbatim: presentation.title)
                    .font(.dm(compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: presentation.body)
                .font(.dm(compact ? 11 : 12.5))
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            actions
                .padding(.top, m.pt(compact ? 0 : 4))
            if showsDetails, !failure.message.isEmpty {
                Text(verbatim: failure.message)
                    .font(.dm(11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(m.pt(10))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dmSurface(Color.black.opacity(0.25), radius: DMRadius.row)
            }
        }
        .padding(m.pt(compact ? 12 : 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmSurface(tint.opacity(0.07), radius: DMRadius.toast, stroke: tint.opacity(0.35))
    }

    @ViewBuilder
    private var actions: some View {
        let size: DMButtonSize = compact ? .small : .regular
        let buttons = presentation.actions
        if compact {
            FlowLayout(spacing: 6) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { index, action in
                    button(action, primary: index == 0, size: size)
                }
                detailsButton
            }
        } else {
            HStack(spacing: m.pt(8)) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { index, action in
                    button(action, primary: index == 0, size: size)
                }
                Spacer()
                detailsButton
            }
        }
    }

    @ViewBuilder
    private var detailsButton: some View {
        if !failure.message.isEmpty {
            DMButton(showsDetails ? "Hide details" : "Show details", variant: .link, size: .small) {
                showsDetails.toggle()
            }
        }
    }

    @ViewBuilder
    private func button(_ action: ChatFailurePresentation.Action, primary: Bool, size: DMButtonSize) -> some View {
        let variant: DMButtonVariant = primary ? .primary : .outline
        switch action {
        case .logIn:
            DMButton("Log in \(place.workspaceName.map { "on \($0)" } ?? "on this Mac")",
                     systemImage: "person.badge.key", variant: variant, size: size) {
                store.awaitLogin(chatID)
                model.openHarnessLogin(harness, place: place)
            }
        case .chooseAnotherWorkspace:
            DMButton("Choose another workspace", variant: variant, size: size) {
                store.askElsewhere(chatID)
                model.showChats()
            }
        case .openPackages:
            DMButton("Open packages", systemImage: "shippingbox", variant: variant, size: size) {
                if let workspace = place.workspaceName { model.openPackages(workspace: workspace) }
            }
        case .openMachines:
            DMButton("Open Machines", systemImage: "server.rack", variant: variant, size: size) {
                model.openSettings(.machines)
            }
        case .updateCLI:
            DMButton("Update the CLI", systemImage: "arrow.down.circle", variant: variant, size: size) {
                if let openCLIUpdate { openCLIUpdate() } else { model.openSettings(.about) }
            }
        case .tryAgain:
            DMButton("Try again", systemImage: "arrow.clockwise", variant: variant, size: size) {
                store.retry(chatID)
            }
        }
    }
}
