import SwiftUI
import DevmachineCore

/// Asks for the raw command a new session runs, with the workspace's recent
/// commands one click away.
struct CustomCommandSheet: View {
    @Environment(\.dmMetrics) private var m
    let workspaceName: String
    let recents: [String]
    let onRun: (String) -> Void
    var onRemove: (String) -> Void = { _ in }
    let onCancel: () -> Void
    @State private var command = ""
    @FocusState private var fieldFocused: Bool

    private var canRun: Bool { CustomSessionCommand.normalized(command) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text("Run a command in \(workspaceName)").font(.headline)
            TextField("command to run", text: $command)
                .font(.dm(13, design: .monospaced))
                .focused($fieldFocused)
                .onSubmit { if canRun { onRun(command) } }
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: m.space.xxs) {
                    DMSectionLabel(text: "RECENT")
                        .padding(.leading, m.space.xs)
                    ForEach(recents, id: \.self) { recent in
                        DMRow(
                            systemImage: "clock.arrow.circlepath",
                            iconSize: 11,
                            title: recent,
                            outerHorizontalPadding: 0,
                            trailingHover: AnyView(
                                DMIconButton(systemImage: "xmark", size: 9) { onRemove(recent) }
                                    .help("Remove from saved commands")),
                            tap: { onRun(recent) })
                            .help(recent)
                    }
                }
            }
            HStack {
                Spacer()
                DMButton("Cancel", variant: .outline, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                DMButton("Run", systemImage: "play.fill") { onRun(command) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRun)
            }
        }
        .padding(m.pt(20))
        .frame(width: m.card.sheet)
        .onAppear { fieldFocused = true }
    }
}
