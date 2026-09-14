import SwiftUI
import AppKit
import DevmachineCore

struct SetupPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var opsRepoPath = ""
    @State private var hostAlias = ""
    @State private var publicIP = ""
    @State private var baseDomain = ""

    private var draft: AppSettings {
        AppSettings(
            opsRepoPath: opsRepoPath.trimmingCharacters(in: .whitespaces),
            hostAlias: hostAlias.trimmingCharacters(in: .whitespaces),
            publicIP: publicIP.trimmingCharacters(in: .whitespaces),
            baseDomain: baseDomain.trimmingCharacters(in: .whitespaces)
        )
    }

    private var issues: [SettingsIssue] { AppSettings.validate(draft) }

    private var isFirstRun: Bool { !settingsStore.isConfigured }

    var body: some View {
        ZStack {
            WallpaperBackground(style: .photo)
            card
                .frame(maxWidth: 480)
                .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear { load() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isFirstRun ? "Welcome" : "Settings")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                Text("The app talks to one host through ssh and keeps its ops repo on this Mac. Tell it where both are.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            field(
                title: "Ops repo folder",
                hint: "Holds \(AppSettings.opsRepoMarker) — the Ansible playbook this app applies.",
                field: .opsRepoPath
            ) {
                HStack(spacing: 8) {
                    TextField("/Users/you/dev/ops", text: $opsRepoPath)
                        .textFieldStyle(.plain)
                        .setupField()
                    Button("Choose…") { chooseFolder() }
                        .buttonStyle(.bordered)
                }
            }

            field(
                title: "Host ssh alias",
                hint: "A Host entry in ~/.ssh/config. Workspaces are the aliases ending in -\(hostAlias.isEmpty ? "alias" : hostAlias).",
                field: .hostAlias
            ) {
                TextField("myhost", text: $hostAlias)
                    .textFieldStyle(.plain)
                    .setupField()
            }

            field(
                title: "Public IP",
                hint: "The A record new subdomains point at.",
                field: .publicIP
            ) {
                TextField("203.0.113.10", text: $publicIP)
                    .textFieldStyle(.plain)
                    .setupField()
            }

            field(
                title: "Base domain",
                hint: "New subdomains are created under it.",
                field: .baseDomain
            ) {
                TextField("example.com", text: $baseDomain)
                    .textFieldStyle(.plain)
                    .setupField()
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Start devmachine") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!issues.isEmpty)
                    .keyboardShortcut(.defaultAction)
                if !isFirstRun {
                    Button("") { model.activePage = nil }
                        .keyboardShortcut(.cancelAction)
                        .hidden()
                        .frame(width: 0, height: 0)
                }
            }
            .controlSize(.large)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func field<Content: View>(
        title: String,
        hint: String,
        field: SettingsIssue.Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            content()
            if let issue = issues.first(where: { $0.field == field }) {
                Text(issue.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() {
        if let current = settingsStore.settings {
            opsRepoPath = current.opsRepoPath
            hostAlias = current.hostAlias
            publicIP = current.publicIP
            baseDomain = current.baseDomain
            return
        }

        let configPath = NSHomeDirectory() + "/.ssh/config"
        let config = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        let proposed = AppSettings.prefill(sshConfig: config, sshResolve: Self.resolveHostname)
        opsRepoPath = proposed.opsRepoPath
        hostAlias = proposed.hostAlias
        publicIP = proposed.publicIP
        baseDomain = proposed.baseDomain
    }

    private static func resolveHostname(_ alias: String) -> String? {
        guard let dump = try? ProcessRunner().run(
            executable: "/usr/bin/ssh", args: ["-G", alias], environment: nil
        ) else { return nil }
        return SSHConfigParser.hostname(inSSHDump: dump)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: opsRepoPath.isEmpty ? NSHomeDirectory() : opsRepoPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        opsRepoPath = url.path
    }

    private func save() {
        let value = draft
        settingsStore.settings = value
        model.settings = value
        model.activePage = nil
        model.loadWorkspaces()
    }
}

private extension View {
    func setupField() -> some View {
        self
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}
