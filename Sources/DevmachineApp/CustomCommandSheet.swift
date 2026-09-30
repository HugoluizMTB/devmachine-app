import SwiftUI
import DevmachineCore

/// Asks for the raw command a new session runs, with the workspace's recent
/// commands one click away.
struct CustomCommandSheet: View {
    let workspaceName: String
    let recents: [String]
    let onRun: (String) -> Void
    var onRemove: (String) -> Void = { _ in }
    let onCancel: () -> Void
    @State private var command = ""
    @FocusState private var fieldFocused: Bool

    private var canRun: Bool { CustomSessionCommand.normalized(command) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run a command in \(workspaceName)").font(.headline)
            TextField("command to run", text: $command)
                .font(.dm(13, design: .monospaced))
                .focused($fieldFocused)
                .onSubmit { if canRun { onRun(command) } }
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    DMSectionLabel(text: "RECENT")
                        .padding(.leading, 4)
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
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Run") { onRun(command) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRun)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { fieldFocused = true }
    }
}
