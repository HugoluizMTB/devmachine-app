import SwiftUI
import AppKit

/// Shown instead of Setup or the normal UI when the devmachine CLI executable
/// is not on disk. The app talks to every machine through it, so nothing else
/// (sweep, stats, context) can work yet — this owns the whole window the same
/// way Setup does until "Check again" finds it.
struct CLIGatePage: View {
    let onCheckAgain: () -> Void

    private static let installCommand = "brew install mydevmachine/tap/devmachine"
    private static let docsURL = URL(string: "https://mydevmachine.sh/getting-started/")!

    @State private var copied = false

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
                Text("Install the devmachine CLI")
                    .font(.dm(18, weight: .semibold))
                    .foregroundStyle(.white)
                Text("The app talks to your machines through it.")
                    .font(.dm(12.5))
                    .foregroundStyle(.white.opacity(0.7))
            }

            installBox

            Button {
                NSWorkspace.shared.open(Self.docsURL)
            } label: {
                Text("mydevmachine.sh/getting-started")
                    .font(.dm(12))
            }
            .buttonStyle(.link)

            Text("After installing, run `devmachine setup` in a terminal to connect a server.")
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

    private var installBox: some View {
        HStack {
            Text(verbatim: Self.installCommand)
                .font(.dm(12.5, design: .monospaced))
                .foregroundStyle(Color.dmRowText)
                .textSelection(.enabled)
            Spacer(minLength: 12)
            Button(copied ? "Copied" : "Copy") { copyInstallCommand() }
                .buttonStyle(.dmChip)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .dmSurface(Color.dmSelection, radius: DMRadius.control)
    }

    private func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.installCommand, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
