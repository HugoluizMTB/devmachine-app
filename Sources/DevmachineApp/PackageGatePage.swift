import SwiftUI
import AppKit

/// Shown after the CLI gate and Setup, when the admin machine does not have
/// the `devmachine-app` package yet — stats, Caddy logs and subdomain logs
/// all run through it instead of raw ssh, so none of those work without it.
struct PackageGatePage: View {
    let machines: [String]
    let onCheckAgain: () -> Void

    @State private var copiedAdd: Set<String> = []
    @State private var copiedSync: Set<String> = []

    private func addCommand(_ machine: String) -> String {
        "devmachine packages add devmachine-app --machine \(machine)"
    }
    private func syncCommand(_ machine: String) -> String { "devmachine sync --machine \(machine)" }

    var body: some View {
        ZStack {
            WallpaperBackground(style: .photo)
            card
                .frame(maxWidth: 560)
                .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add the devmachine-app package")
                    .font(.dm(18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(verbatim: summary)
                    .font(.dm(12.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(machines, id: \.self) { machine in
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: machine)
                        .font(.dm(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    commandBox(addCommand(machine), copied: copiedBinding($copiedAdd, machine))
                    commandBox(syncCommand(machine), copied: copiedBinding($copiedSync, machine))
                }
            }

            Text("Sync installs the package on the server; nothing changes until it runs.")
                .font(.dm(11.5))
                .foregroundStyle(.white.opacity(0.55))

            HStack {
                Spacer()
                Button("Check again", action: onCheckAgain)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .dmGlass(radius: DMRadius.panel, style: .continuous, stroke: .white.opacity(0.14))
        .background(
            Color.black.opacity(0.35),
            in: RoundedRectangle(cornerRadius: DMRadius.panel, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var summary: String {
        machines.count == 1
            ? "\"\(machines[0])\" needs it for stats, Caddy logs and subdomain logs — "
                + "the app no longer reads those over raw ssh."
            : "These machines need it for stats, Caddy logs and subdomain logs — "
                + "the app no longer reads those over raw ssh."
    }

    private func copiedBinding(_ set: Binding<Set<String>>, _ machine: String) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(machine) },
            set: { isCopied in
                if isCopied { set.wrappedValue.insert(machine) } else { set.wrappedValue.remove(machine) }
            }
        )
    }

    private func commandBox(_ command: String, copied: Binding<Bool>) -> some View {
        HStack {
            Text(verbatim: command)
                .font(.dm(12.5, design: .monospaced))
                .foregroundStyle(Color.dmRowText)
                .textSelection(.enabled)
            Spacer(minLength: 12)
            Button(copied.wrappedValue ? "Copied" : "Copy") { copy(command, into: copied) }
                .buttonStyle(.dmChip)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .dmSurface(Color.dmSelection, radius: DMRadius.control)
    }

    private func copy(_ command: String, into copied: Binding<Bool>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied.wrappedValue = false }
    }
}
