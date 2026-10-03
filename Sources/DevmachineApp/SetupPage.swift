import SwiftUI
import AppKit
import DevmachineCore

/// The panes of Settings. One column held every field before, which made a
/// change to the font size a scroll past every wallpaper.
enum SettingsSection: String, CaseIterable {
    case connection, machines, workspaces, harnesses, appearance, terminal, previews, advanced, about

    var title: String {
        switch self {
        case .connection: return "Connection"
        case .machines: return "Machines"
        case .workspaces: return "Workspaces"
        case .harnesses: return "Harnesses"
        case .appearance: return "Appearance"
        case .terminal: return "Terminal"
        case .previews: return "Previews"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .connection: return "The host this app talks to, and the devmachine configuration it reads."
        case .machines: return "The servers and local machines in the devmachine configuration."
        case .workspaces: return "Which workspaces the sidebar shows and the app reaches."
        case .harnesses: return "Choose what new sessions start with."
        case .appearance: return "The wallpaper behind the panes, and the size of the interface."
        case .terminal: return "How a terminal looks, and how many stay connected."
        case .previews: return "Where a dev server, a published site or a link opens."
        case .advanced: return "Things to turn on only while chasing a problem."
        case .about: return "This app's version and updates, and the devmachine CLI's."
        }
    }

    var systemImage: String {
        switch self {
        case .connection: return "network"
        case .machines: return "server.rack"
        case .workspaces: return "square.grid.2x2"
        case .harnesses: return "sparkles"
        case .appearance: return "photo"
        case .terminal: return "terminal"
        case .previews: return "safari"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }

    /// Every field that can fail validation lives in Connection, so that is the
    /// pane the rail marks when something is wrong.
    var showsValidation: Bool { self == .connection }
}

private enum LaunchChoiceTag: Hashable {
    case terminal
    case harness(HarnessID)
    case custom(String)
    case typing

    init(_ choice: SessionLaunchChoice) {
        switch choice {
        case .terminal:
            self = .terminal
        case let .harness(id):
            self = .harness(id)
        case let .custom(raw):
            self = CustomSessionCommand.normalized(raw).map(LaunchChoiceTag.custom) ?? .typing
        }
    }

    func choice(replacing current: SessionLaunchChoice) -> SessionLaunchChoice {
        switch self {
        case .terminal:
            return .terminal
        case let .harness(id):
            return .harness(id)
        case let .custom(command):
            return .custom(command)
        case .typing:
            if case .custom = current { return current }
            return .custom("")
        }
    }
}

struct SetupPage: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var wallpapers: WallpaperStore
    @EnvironmentObject var savedCommands: RecentCommandStore
    @Environment(\.harnessSettingsFacade) private var harnessSettingsFacade
    @ObservedObject private var machinesStore = MachinesStore.shared

    /// Not a theme id in the library — the chip that shows the built-in gradients.
    static let gradientTheme = "gradient"

    @State private var opsRepoPath = ""
    @State private var hostAlias = ""
    @State private var publicIP = ""
    @State private var baseDomain = ""
    @State private var sshAgentSocket = ""
    @State private var wallpaper = WallpaperChoice.bundled
    @State private var themeID = SetupPage.gradientTheme
    @State private var terminalOpacity = Appearance.defaultTerminalOpacity
    @State private var terminalFontSize = Appearance.defaultTerminalFontSize
    @State private var uiFontScale = Appearance.defaultUIFontScale
    @State private var keptTerminals = Appearance.defaultKeptTerminals
    @State private var debugLogging = false
    @State private var remoteTerminalMode = RemoteTerminalMode.automatic
    @State private var copyOnSelect = true
    @State private var showsHarnessIcons = false
    @State private var harnessIconStyle = HarnessIconStyle.color
    @State private var linkOpening = LinkOpening.defaultBrowser
    @State private var hiddenWorkspaces: [String] = []
    @State private var enabledHarnesses = AppSettings.empty.enabledHarnesses
    @State private var localSessionProgram = SessionLaunchChoice.terminal
    @State private var remoteSessionProgram = SessionLaunchChoice.terminal
    @State private var workspaceSessionPrograms: [String: SessionLaunchChoice] = [:]
    @State private var harnessErrors: [HarnessID: String] = [:]
    /// Bumped once the CLIs on this Mac were looked up again, to redraw
    /// what depends on them.
    @State private var cliAvailabilityRead = 0
    /// Connection fields opened for typing. A field with a value shows it
    /// read-only until "Edit": what the CLI reports is rarely changed.
    @State private var editing: Set<SettingsIssue.Field> = []

    private var draft: AppSettings {
        AppSettings(
            opsRepoPath: opsRepoPath.trimmingCharacters(in: .whitespaces),
            hostAlias: hostAlias.trimmingCharacters(in: .whitespaces),
            publicIP: publicIP.trimmingCharacters(in: .whitespaces),
            baseDomain: baseDomain.trimmingCharacters(in: .whitespaces),
            sshAgentSocket: sshAgentSocket.trimmingCharacters(in: .whitespaces),
            wallpaper: wallpaper,
            terminalOpacity: terminalOpacity,
            terminalFontSize: terminalFontSize,
            uiFontScale: uiFontScale,
            keptTerminals: keptTerminals,
            debugLogging: debugLogging,
            remoteTerminalMode: remoteTerminalMode,
            copyOnSelect: copyOnSelect,
            showsHarnessIcons: showsHarnessIcons,
            harnessIconStyle: harnessIconStyle,
            hiddenWorkspaces: hiddenWorkspaces,
            enabledHarnesses: enabledHarnesses,
            localSessionProgram: localSessionProgram,
            remoteSessionProgram: remoteSessionProgram,
            workspaceSessionPrograms: workspaceSessionPrograms,
            linkOpening: linkOpening
        )
    }

    private var issues: [SettingsIssue] { Self.issues(for: draft, cliConfigDirectory: model.detected.opsRepoPath) }

    /// The demo's folder and CLI are invented, so they are never looked up on
    /// this Mac: a screenshot must not warn about the owner's own disk.
    static func issues(
        for draft: AppSettings, cliConfigDirectory: String? = nil, demo: Bool = DemoMode.isActive
    ) -> [SettingsIssue] {
        guard !demo else {
            let remedy = DemoSnapshots.settingsIssueRemedy
            return AppSettings.validate(
                draft, fileExists: { remedy != .runSetup || !$0.hasSuffix(AppSettings.opsRepoMarker) },
                cliExecutableFound: remedy != .installCLI)
        }
        return AppSettings.validate(
            draft, cliExecutableFound: (try? DevmachineCLI.resolve()) != nil, cliConfigDirectory: cliConfigDirectory)
    }

    private var notices: [SettingsNotice] {
        Self.notices(for: draft, cliConfigDirectory: model.detected.opsRepoPath)
    }

    static func notices(
        for draft: AppSettings, cliConfigDirectory: String? = nil, demo: Bool = DemoMode.isActive
    ) -> [SettingsNotice] {
        guard !demo else {
            guard DemoSnapshots.settingsNoMachine else { return [] }
            return AppSettings.notices(draft, fileExists: { _ in false }, cliConfigDirectory: draft.opsRepoPath)
        }
        return AppSettings.notices(
            draft, cliExecutableFound: (try? DevmachineCLI.resolve()) != nil, cliConfigDirectory: cliConfigDirectory)
    }

    private var isFirstRun: Bool { !settingsStore.isConfigured }

    @State private var section: SettingsSection

    /// `initialSection` only ever differs from `.connection` for the
    /// website's demo screenshots, which need to open straight onto Health.
    init(initialSection: SettingsSection = .connection) {
        _section = State(initialValue: initialSection)
    }

    /// A central page like any other, with the sidebar beside it: Settings →
    /// Machines → Add a machine stays one place instead of a window over the app.
    var body: some View {
        card
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dmContentBg)
            .onAppear {
                load()
                openRequestedSection()
            }
            .task {
                // The CLI may have been installed or set up since launch.
                await model.refreshDetected()
                fillFromDetected()
            }
            .task {
                let facade = harnessSettingsFacade
                await Task.detached { facade.refreshAvailability() }.value
                cliAvailabilityRead += 1
            }
            .onChange(of: model.requestedSettingsSection) { _, _ in openRequestedSection() }
    }

    private func openRequestedSection() {
        guard let requested = model.requestedSettingsSection else { return }
        section = requested
        model.requestedSettingsSection = nil
    }

    private var card: some View {
        HStack(spacing: 0) {
            rail
                .background(Color.dmBand)
            VStack(spacing: 0) {
                sectionBody
                footer
            }
            .frame(maxWidth: m.pt(880), maxHeight: .infinity)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.colorScheme, .dark)
    }

    /// The list of sections. Everything used to be one column, so a change to
    /// the font size meant scrolling past every wallpaper.
    private var rail: some View {
        VStack(alignment: .leading, spacing: m.space.xxs) {
            VStack(alignment: .leading, spacing: m.pt(3)) {
                Text(isFirstRun ? "Welcome" : "Settings")
                    .font(.dm(18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(isFirstRun ? "Tell the app where the host is." : "Devmachine")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, m.pt(14))
            .padding(.top, m.pt(18))
            .padding(.bottom, m.pt(14))

            ForEach(SettingsSection.allCases, id: \.self) { item in
                railRow(item)
            }
            Spacer(minLength: 0)
        }
        .frame(width: m.pt(208))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func railRow(_ item: SettingsSection) -> some View {
        let selected = section == item
        let broken = item.showsValidation && !issues.isEmpty
        return HStack(spacing: m.space.md) {
            Image(systemName: item.systemImage)
                .font(.dm(11))
                .frame(width: m.pt(16))
                .foregroundStyle(selected ? .white : .white.opacity(0.6))
            Text(item.title)
                .font(.dm(12.5))
                .foregroundStyle(selected ? .white : .white.opacity(0.75))
            Spacer(minLength: m.space.xs)
            if broken {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.dm(10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, m.pt(10))
        .padding(.vertical, m.pt(7))
        .background(
            DMRowBackground(
                selected: selected, cornerRadius: DMRadius.control, style: .continuous,
                selectedColor: .white.opacity(0.14)))
        .padding(.horizontal, m.space.md)
        .contentShape(Rectangle())
        .onTapGesture { section = item }
    }

    private var sectionBody: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: m.pt(18)) {
                VStack(alignment: .leading, spacing: m.space.xs) {
                    Text(section.title)
                        .font(.dm(15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(section.subtitle)
                        .font(.dm(11))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                switch section {
                case .connection: connectionBlock
                case .machines: MachinesSettingsView()
                case .workspaces: workspacesBlock
                case .harnesses: harnessesBlock.task { await machinesStore.load() }
                case .appearance: wallpaperBlock
                case .terminal: terminalBlock
                case .previews: previewsBlock
                case .advanced: advancedBlock
                case .about: UpdatesSettingsView()
                }
            }
            .padding(m.space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: m.pt(10)) {
            if let issue = issues.first {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.dm(11))
                    .foregroundStyle(.orange)
                Text(issue.message)
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                if issue.remedy != nil {
                    DMButton("Run the setup", systemImage: "play.fill", variant: .outline, size: .small) {
                        model.openOnboarding()
                    }
                }
            } else if let notice = notices.first {
                Image(systemName: "info.circle.fill")
                    .font(.dm(11))
                    .foregroundStyle(.blue)
                Text(notice.message)
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            if !isFirstRun {
                DMButton("Cancel", variant: .outline) { model.activePage = nil }
                    .keyboardShortcut(.cancelAction)
            }
            DMButton(isFirstRun ? "Start devmachine" : "Save") { save() }
                .disabled(!issues.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.regular)
        .padding(.horizontal, m.pt(20))
        .padding(.vertical, m.pt(14))
    }

    private var connectionBlock: some View {
        VStack(alignment: .leading, spacing: m.space.xl) {
            field(
                title: "Configuration folder",
                hint: "Where the devmachine CLI keeps \(AppSettings.opsRepoMarker). The CLI chose it; "
                    + "change it only to use another configuration.",
                field: .opsRepoPath
            ) {
                valueRow(
                    opsRepoPath.isEmpty ? nil : Self.displayPath(opsRepoPath),
                    empty: "Not set up yet",
                    button: opsRepoPath.isEmpty ? "Choose…" : "Change…",
                    action: chooseFolder)
            }

            editableField(
                title: "Public IP",
                hint: "The A record new subdomains point at. Leave it empty without a server.",
                field: .publicIP, text: $publicIP, placeholder: "203.0.113.10")

            editableField(
                title: "Base domain",
                hint: "New subdomains are created under it. Leave it empty without a server.",
                field: .baseDomain, text: $baseDomain, placeholder: "example.com")

            editableField(
                title: "Host ssh alias",
                hint: "Optional. Empty means \"devmachine\", the name `devmachine aliases --write` gives "
                    + "every workspace's ssh alias (the aliases ending in -\(hostAlias.isEmpty ? "devmachine" : hostAlias)). "
                    + "Admin commands (stats, Caddy) run through the devmachine CLI and do not need it.",
                field: .hostAlias, text: $hostAlias, placeholder: "devmachine",
                emptyValue: "devmachine (default)")

            VStack(alignment: .leading, spacing: m.pt(5)) {
                Text(verbatim: "SSH agent socket")
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                TextField("Leave empty to detect it automatically", text: $sshAgentSocket)
                    .dmField()
                note("Only needed if 1Password's agent is not what this Mac should use. "
                    + "Empty tries the 1Password socket, then the ssh agent already running.")
            }
        }
    }

    /// A value shown as it is, with one button to change it. Detected values
    /// are rarely edited, so they read as facts, not as blank inputs.
    private func valueRow(
        _ value: String?, empty: String, button: String, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: m.space.md) {
            Text(verbatim: value ?? empty)
                .font(.dm(12, design: value == nil ? .default : .monospaced))
                .foregroundStyle(value == nil ? .white.opacity(0.45) : .white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: m.space.md)
            DMButton(button, variant: .outline, size: .small, action: action)
        }
        .padding(.leading, m.row.horizontal)
        .padding(.trailing, m.space.xs)
        .padding(.vertical, m.space.xs)
        .dmSurface(Color.dmSelection, radius: DMRadius.row, style: .continuous)
    }

    /// Read-only with "Edit" when it has a value; a text field when it has
    /// none yet or the person asked to change it.
    @ViewBuilder
    private func editableField(
        title: String, hint: String, field: SettingsIssue.Field, text: Binding<String>,
        placeholder: String, emptyValue: String? = nil
    ) -> some View {
        self.field(title: title, hint: hint, field: field) {
            let value = text.wrappedValue
            if editing.contains(field) || (value.isEmpty && emptyValue == nil) {
                TextField(placeholder, text: text)
                    .dmField()
            } else {
                valueRow(value.isEmpty ? emptyValue : value, empty: placeholder, button: "Edit") {
                    editing.insert(field)
                }
            }
        }
    }

    /// `~` for the home folder: a full `/Users/<name>/.config/…` path is
    /// longer and says nothing more.
    static func displayPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    @ViewBuilder
    private func field<Content: View>(
        title: String,
        hint: String,
        field: SettingsIssue.Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: m.pt(5)) {
            Text(title)
                .font(.dm(11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            content()
            if let issue = issues.first(where: { $0.field == field }) {
                Text(issue.message)
                    .font(.dm(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let remedy = issue.remedy {
                    DMButton(
                        remedy == .installCLI ? "Set up devmachine" : "Run devmachine setup",
                        systemImage: "play.fill", size: .small
                    ) { model.openOnboarding() }
                }
            } else if let notice = notices.first(where: { $0.field == field }) {
                Text(notice.message)
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: m.space.sm) {
                    DMButton("Run setup", systemImage: "play.fill", size: .small) { model.openOnboarding() }
                    DMButton("Add a machine", systemImage: "plus", variant: .outline, size: .small) {
                        model.showPage(.addMachine)
                    }
                }
            } else if isDetected(field) {
                Text("Detected from the devmachine CLI.")
                    .font(.dm(11))
                    .foregroundStyle(.blue)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(hint)
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A list of what to hide, never of what to show: a workspace that appears
    /// in `~/.ssh/config` later is visible without anyone opening Settings.
    private var workspacesBlock: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            HStack(spacing: m.space.md) {
                Text(verbatim: "Add, change, forget or destroy a workspace on the Workspaces page. "
                    + "Here you only choose which ones the sidebar shows.")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                DMButton("Manage workspaces…", systemImage: "square.grid.2x2", variant: .outline, size: .small) {
                    model.showPage(.workspaces)
                }
            }
            workspaceVisibility
        }
    }

    @ViewBuilder
    private var workspaceVisibility: some View {
        if model.workspaces.isEmpty {
            note("No workspace yet. They are the ssh aliases ending in "
                + "-\(hostAlias.isEmpty ? "devmachine" : hostAlias); the app reads them from "
                + "~/.ssh/config once the host above is set.")
        } else {
            VStack(alignment: .leading, spacing: m.pt(10)) {
                ForEach(model.workspaces, id: \.alias) { workspace in
                    Toggle(isOn: Binding(
                        get: {
                            !WorkspaceVisibility.isHidden(
                                workspace.alias, hidden: hiddenWorkspaces)
                        },
                        set: { _ in
                            hiddenWorkspaces = WorkspaceVisibility.toggling(
                                workspace.alias, in: hiddenWorkspaces)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(workspace.name)
                                .font(.dm(12.5))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(workspace.alias)
                                .font(.dm(10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                note("A workspace turned off leaves the sidebar, and the app stops "
                    + "reaching its host: no ssh, no mosh, no poll. Its sessions keep "
                    + "running on the host and come back the moment you turn it on "
                    + "again. This Mac cannot be turned off.")
            }
        }
    }

    private func harnessLabel(_ descriptor: HarnessDescriptor, detail: String) -> some View {
        HStack(spacing: m.space.md) {
            Image(systemName: descriptor.systemImage)
                .font(.dm(10))
                .foregroundStyle(descriptor.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: descriptor.title)
                    .font(.dm(12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text(verbatim: detail)
                    .font(.dm(10))
                    .foregroundStyle(.white.opacity(0.45))
                if let note = remoteOnlyNote(descriptor.id) {
                    Text(verbatim: note)
                        .font(.dm(10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    private var harnessesBlock: some View {
        VStack(alignment: .leading, spacing: m.pt(30)) {
            VStack(alignment: .leading, spacing: m.pt(10)) {
                settingsHeading("Available harnesses")
                let activatable = Set(harnessSettingsFacade.activatable(
                    available: machinesStore.workspacePackageNames).map(\.id))
                ForEach(harnessSettingsFacade.harnesses) { descriptor in
                    VStack(alignment: .leading, spacing: m.space.xs) {
                        if activatable.contains(descriptor.id) {
                            Toggle(isOn: harnessEnabledBinding(descriptor.id)) {
                                harnessLabel(
                                    descriptor, detail: "Make \(descriptor.shortTitle) available for session defaults "
                                        + "and new workspaces.")
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        } else {
                            harnessLabel(
                                descriptor, detail: "Recognized in sessions. No package in this release installs it, "
                                    + "so it cannot be turned on.")
                        }

                        if let message = harnessErrors[descriptor.id] {
                            Text(verbatim: message)
                                .font(.dm(10))
                                .foregroundStyle(.orange)
                                .padding(.leading, m.space.xxl)
                        }
                    }
                }
                note("Turning a harness on adds it to the launch choices and to a new workspace's "
                    + "coding agents. Starting it on this Mac needs its CLI here; a remote workspace "
                    + "never asks. Every harness is recognized in a session either way.")
            }

            harnessIconToggle

            VStack(alignment: .leading, spacing: m.pt(10)) {
                settingsHeading("Session defaults")
                launchChoicePicker(
                    title: "This Mac",
                    detail: "New local sessions",
                    savedFor: Workspace.local.alias,
                    place: .thisMac,
                    selection: $localSessionProgram
                )
                launchChoicePicker(
                    title: "Remote fallback",
                    detail: "New workspaces inherit this choice",
                    savedFor: RecentCommandStore.remoteFallback,
                    selection: $remoteSessionProgram
                )

                if model.visibleWorkspaces.isEmpty {
                    note("Workspace overrides appear for workspaces enabled above.")
                } else {
                    ForEach(model.visibleWorkspaces) { workspace in
                        launchChoicePicker(
                            title: workspace.name,
                            detail: workspace.alias,
                            savedFor: workspace.alias,
                            showsCommandField: workspaceSessionPrograms[workspace.alias] != nil,
                            selection: workspaceChoiceBinding(workspace.alias)
                        )
                        if workspaceSessionPrograms[workspace.alias] != nil {
                            DMButton("Use remote fallback", variant: .link, size: .small) {
                                workspaceSessionPrograms.removeValue(forKey: workspace.alias)
                            }
                        }
                    }
                }

                note("A harness or a custom command is typed into the new shell, "
                    + "exactly as written. Leaving it keeps the session open, and "
                    + "sessions that already exist are never touched. An empty "
                    + "custom command opens a plain terminal.")
            }
        }
    }

    private func settingsHeading(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.dm(11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
    }

    private func launchChoicePicker(
        title: String,
        detail: String,
        savedFor alias: String,
        place: LaunchPlace = .remote,
        showsCommandField: Bool = true,
        selection: Binding<SessionLaunchChoice>
    ) -> some View {
        let options = launchOptions(on: place)
        return VStack(alignment: .trailing, spacing: m.space.sm) {
            HStack(spacing: m.space.lg) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.dm(12))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(verbatim: detail)
                        .font(.dm(10))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer(minLength: m.space.md)
                Picker("", selection: Binding(
                    get: { LaunchChoiceTag(Self.offered(selection.wrappedValue, in: options)) },
                    set: { selection.wrappedValue = $0.choice(replacing: selection.wrappedValue) }
                )) {
                    ForEach(options) { option in
                        Text(verbatim: option.title)
                            .tag(LaunchChoiceTag(option.choice))
                    }
                    let commands = commandChoices(savedFor: alias, current: selection.wrappedValue)
                    if !commands.isEmpty {
                        Divider()
                        ForEach(commands, id: \.self) { command in
                            Text(verbatim: command)
                                .tag(LaunchChoiceTag.custom(command))
                        }
                    }
                    Divider()
                    Text(verbatim: "Custom command…")
                        .tag(LaunchChoiceTag.typing)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: m.pt(170))
            }
            if showsCommandField, case let .custom(command) = selection.wrappedValue {
                TextField("command to run, e.g. npm run dev", text: Binding(
                    get: { command },
                    set: { selection.wrappedValue = .custom($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.dm(12, design: .monospaced))
                .controlSize(.small)
                .frame(maxWidth: m.pt(360))
            }
        }
    }

    /// The saved commands for a row, plus the one it runs now when that is
    /// being typed or came from a list it does not own (an inherited fallback).
    private func commandChoices(savedFor alias: String, current: SessionLaunchChoice) -> [String] {
        let saved = savedCommands.recents(for: alias)
        guard case let .custom(raw) = current,
              let command = CustomSessionCommand.normalized(raw),
              !saved.contains(command) else { return saved }
        return saved + [command]
    }

    /// A custom default saved here becomes one click away in the same
    /// workspace's "+" menu.
    private func rememberCustomDefaults(_ settings: AppSettings) {
        if case let .custom(command) = settings.localSessionProgram {
            savedCommands.remember(command, for: Workspace.local.alias)
        }
        if case let .custom(command) = settings.remoteSessionProgram {
            savedCommands.remember(command, for: RecentCommandStore.remoteFallback)
        }
        for (alias, choice) in settings.workspaceSessionPrograms {
            if case let .custom(command) = choice {
                savedCommands.remember(command, for: alias)
            }
        }
    }

    private func launchOptions(on place: LaunchPlace) -> [HarnessLaunchOption] {
        _ = cliAvailabilityRead
        return SettingsDraft(value: draft).launchOptions(using: harnessSettingsFacade, on: place)
    }

    private func remoteOnlyNote(_ id: HarnessID) -> String? {
        _ = cliAvailabilityRead
        return harnessSettingsFacade.remoteOnlyNote(for: id, in: draft)
    }

    /// A harness this list does not offer (its CLI is not on this Mac) shows
    /// as the plain shell it falls back to.
    static func offered(_ choice: SessionLaunchChoice, in options: [HarnessLaunchOption]) -> SessionLaunchChoice {
        guard case .harness = choice, !options.contains(where: { $0.choice == choice }) else { return choice }
        return .terminal
    }

    private func harnessEnabledBinding(_ id: HarnessID) -> Binding<Bool> {
        Binding(
            get: { enabledHarnesses.contains(id) },
            set: { setHarness(id, enabled: $0) }
        )
    }

    private func workspaceChoiceBinding(_ alias: String) -> Binding<SessionLaunchChoice> {
        Binding(
            get: { workspaceSessionPrograms[alias] ?? remoteSessionProgram },
            set: { workspaceSessionPrograms[alias] = $0 }
        )
    }

    private func setHarness(_ id: HarnessID, enabled: Bool) {
        var candidate = SettingsDraft(value: draft)
        let result = candidate.setHarness(id, enabled: enabled, using: harnessSettingsFacade)
        switch result {
        case .success:
            harnessErrors[id] = nil
            applyHarnessSettings(candidate.value)
        case let .failure(error):
            harnessErrors[id] = harnessActivationMessage(error)
        }
    }

    private func applyHarnessSettings(_ settings: AppSettings) {
        enabledHarnesses = settings.enabledHarnesses
        localSessionProgram = settings.localSessionProgram
        remoteSessionProgram = settings.remoteSessionProgram
        workspaceSessionPrograms = settings.workspaceSessionPrograms
    }

    private func harnessActivationMessage(_ error: HarnessActivationError) -> String {
        switch error {
        case .harnessNotRegistered:
            return "This harness is not available."
        }
    }

    private var terminalBlock: some View {
        VStack(alignment: .leading, spacing: m.pt(14)) {
            slider(
                title: "Terminal transparency",
                value: $terminalOpacity,
                range: Appearance.terminalOpacityRange,
                // Shown the way you read it: more transparency, less opacity.
                reading: "\(Int(((1 - terminalOpacity) * 100).rounded()))%"
            )
            slider(
                title: "Terminal font size",
                value: $terminalFontSize,
                range: Appearance.terminalFontSizeRange,
                step: 1,
                reading: "\(Int(terminalFontSize.rounded())) pt"
            )
            slider(
                title: "Sessions kept connected",
                value: Binding(
                    get: { Double(keptTerminals) },
                    set: { keptTerminals = Appearance.clampKeptTerminals(Int($0.rounded())) }
                ),
                range: Appearance.keptTerminalsSliderRange,
                step: 1,
                reading: "\(keptTerminals)"
            )
            note("A session you are not looking at stays connected, so switching "
                + "back to it is instant. Each one costs a client process and its "
                + "scrollback. Past this many, the one left alone the longest is "
                + "disconnected; the session on the other side keeps running and "
                + "reconnects when you return. Keep it above your number of "
                + "workspaces.")
            copyOnSelectToggle
            remoteTerminalPicker
        }
    }

    private var harnessIconToggle: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            settingsHeading("Sidebar")
            Toggle(isOn: $showsHarnessIcons) {
                Text(verbatim: "Show harness icon in sidebar sessions")
                    .font(.dm(12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            note("A session running a harness shows its icon before the name. "
                + "Terminal sessions show none.")
            HStack(spacing: m.space.lg) {
                Text(verbatim: "Icon style")
                    .font(.dm(12))
                    .foregroundStyle(.white.opacity(showsHarnessIcons ? 0.85 : 0.4))
                Picker("", selection: $harnessIconStyle) {
                    ForEach(HarnessIconStyle.allCases, id: \.self) { style in
                        Text(verbatim: style.title).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }
            .disabled(!showsHarnessIcons)
        }
    }

    private var copyOnSelectToggle: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            Toggle(isOn: $copyOnSelect) {
                Text(verbatim: "Copy on select")
                    .font(.dm(12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            note("Text you select with the mouse goes to the clipboard when you let "
                + "go, in every session. \u{2318}C copies it too. A click clears the "
                + "selection, a double-click selects a word and a triple-click a line.")
        }
    }

    private var remoteTerminalPicker: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            HStack(spacing: m.space.lg) {
                Text(verbatim: "Remote terminals")
                    .font(.dm(12))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: m.space.md)
                Picker("", selection: $remoteTerminalMode) {
                    ForEach(RemoteTerminalMode.allCases, id: \.self) { mode in
                        Text(verbatim: mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: m.pt(260))
            }
            note("mosh keeps a session through sleep, a new Wi-Fi and a slow link. "
                + "It needs mosh-server on the machine and UDP 60000\u{2013}61000 open "
                + "to this Mac. Automatic tries it and switches a pane to ssh within "
                + "five seconds when nothing comes back, then uses ssh for that "
                + "machine for 30 minutes. A change applies to panes opened after it.")
        }
    }

    private var previewsBlock: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            HStack(spacing: m.space.lg) {
                Text(verbatim: "Open previews and links in")
                    .font(.dm(12))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: m.space.md)
                Picker("", selection: $linkOpening) {
                    ForEach(LinkOpening.allCases, id: \.self) { choice in
                        Text(verbatim: choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: m.pt(190))
            }
            note("Applies to the Preview tab's sites and dev servers and to the pull "
                + "requests and links in the Context tab. ⌥-click opens the other way, "
                + "once. In Devmachine, a preview is a tab beside the terminal; its "
                + "cookies and logins last until the app quits. A dev server on a "
                + "workspace is reached through devmachine tunnel, bound to this Mac "
                + "only, and the tunnel closes with its tab or when the app quits.")
        }
    }

    private var advancedBlock: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            Toggle(isOn: $debugLogging) {
                Text(verbatim: "Debug logging")
                    .font(.dm(12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            note("Writes what happens around a terminal — the size a program is "
                + "given, when it starts, when a pane is put away and brought back "
                + "— to ~/.devmachine-app/terminal.log. Turn it on only while "
                + "chasing something; off, nothing is written. The file keeps "
                + "itself under a megabyte.")

            HealthCheckView()
                .padding(.top, m.pt(20))
        }
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(10))
            .foregroundStyle(.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func slider(
        title: String, value: Binding<Double>, range: ClosedRange<Double>,
        step: Double = 0.01, reading: String
    ) -> some View {
        VStack(alignment: .leading, spacing: m.space.xxs) {
            HStack {
                Text(verbatim: title)
                    .font(.dm(12))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(verbatim: reading)
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private var wallpaperBlock: some View {
        VStack(alignment: .leading, spacing: m.pt(14)) {
            slider(
                title: "App font size",
                value: $uiFontScale,
                range: Appearance.uiFontScaleRange,
                step: 0.05,
                reading: "\(Int((uiFontScale * 100).rounded()))%"
            )
            Text(verbatim: "Wallpaper")
                .font(.dm(11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            FlowLayout(spacing: 6, rowSpacing: 6) {
                chip(id: Self.gradientTheme, title: "Gradient")
                ForEach(wallpapers.themes) { theme in
                    chip(id: theme.id, title: theme.title)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                if themeID == Self.gradientTheme {
                    ForEach(WallpaperGradient.all) { gradientCell($0) }
                } else if let theme = wallpapers.library.theme(id: themeID) {
                    ForEach(theme.photos) { photoCell($0) }
                }
            }

            credit
                .font(.dm(11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func chip(id: String, title: String) -> some View {
        DMChip(title: title, selected: themeID == id) { themeID = id }
    }

    private func photoCell(_ photo: WallpaperPhoto) -> some View {
        ZStack {
            Color.white.opacity(0.06)
            if let image = wallpapers.thumbnails[photo.id] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    // A scaledToFill thumbnail overflows its cell and its overflow
                    // would swallow the taps of the neighbouring cells.
                    .allowsHitTesting(false)
            }
        }
        .frame(height: m.pt(62))
        .clipShape(RoundedRectangle(cornerRadius: m.radius.tile, style: .continuous))
        .overlay(ring(selected: wallpaper == Self.choice(for: photo)))
        .contentShape(RoundedRectangle(cornerRadius: m.radius.tile, style: .continuous))
        .onTapGesture { select(photo) }
        .onAppear { wallpapers.ensureThumbnail(photo) }
    }

    @ViewBuilder
    private func gradientSwatch(_ gradient: WallpaperGradient) -> some View {
        if gradient.isLandscape, let image = gradient.bitmap(width: 240, height: 150) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            gradient.swatch
        }
    }

    private func gradientCell(_ gradient: WallpaperGradient) -> some View {
        gradientSwatch(gradient)
            .frame(height: m.pt(62))
            .clipShape(RoundedRectangle(cornerRadius: m.radius.tile, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(verbatim: gradient.title)
                    .font(.dm(10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(m.space.sm)
            }
            .overlay(ring(selected: wallpaper == .gradient(name: gradient.name)))
            .contentShape(RoundedRectangle(cornerRadius: m.radius.tile, style: .continuous))
            .onTapGesture { wallpaper = .gradient(name: gradient.name) }
    }

    private func ring(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: m.radius.tile, style: .continuous)
            .stroke(
                selected ? Color.accentColor : Color.dmStroke,
                lineWidth: selected ? 2 : 0.5
            )
    }

    @ViewBuilder
    private var credit: some View {
        if let photo = creditPhoto {
            if let page = wallpapers.library.pageURL(photo) {
                Link(destination: page) { Text(photo.credit) }
            } else {
                Text(photo.credit)
            }
        } else {
            Text(verbatim: "Built-in gradient")
        }
    }

    private var creditPhoto: WallpaperPhoto? {
        switch wallpaper {
        case .gradient:
            return nil
        case .bundled:
            return wallpapers.library.bundledPhoto
        case .unsplash(let id):
            return wallpapers.library.photo(id: id)
        }
    }

    /// The photo the app already ships needs no download, so its cell keeps the
    /// `.bundled` choice instead of a second, identical-looking Unsplash one.
    static func choice(for photo: WallpaperPhoto) -> WallpaperChoice {
        photo.bundled ? .bundled : .unsplash(id: photo.id)
    }

    /// The chip that opens with a choice already made: its theme, or the first one.
    static func openThemeID(for choice: WallpaperChoice, in library: WallpaperLibrary) -> String {
        if case .gradient = choice { return gradientTheme }

        let photoID: String?
        switch choice {
        case .bundled: photoID = library.bundledPhoto?.id
        case .unsplash(let id): photoID = id
        case .gradient: photoID = nil
        }

        let theme = photoID.flatMap { library.theme(ofPhoto: $0) } ?? library.themes.first
        return theme?.id ?? gradientTheme
    }

    private func select(_ photo: WallpaperPhoto) {
        wallpaper = Self.choice(for: photo)
        if !photo.bundled {
            wallpapers.ensure(photo, force: true)
        }
    }

    private func load() {
        wallpaper = settingsStore.settings?.wallpaper ?? .bundled
        themeID = Self.openThemeID(for: wallpaper, in: wallpapers.library)

        if let current = settingsStore.settings {
            opsRepoPath = current.opsRepoPath
            hostAlias = current.hostAlias
            publicIP = current.publicIP
            baseDomain = current.baseDomain
            sshAgentSocket = current.sshAgentSocket
            terminalOpacity = current.terminalOpacity
            terminalFontSize = current.terminalFontSize
            uiFontScale = current.uiFontScale
            keptTerminals = current.keptTerminals
            debugLogging = current.debugLogging
            remoteTerminalMode = current.remoteTerminalMode
            copyOnSelect = current.copyOnSelect
            showsHarnessIcons = current.showsHarnessIcons
            harnessIconStyle = current.harnessIconStyle
            linkOpening = current.linkOpening
            hiddenWorkspaces = current.hiddenWorkspaces
            applyHarnessSettings(current)
        } else {
            let configPath = NSHomeDirectory() + "/.ssh/config"
            let config = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
            let proposed = AppSettings.prefill(sshConfig: config, sshResolve: Self.resolveHostname)
            opsRepoPath = proposed.opsRepoPath
            hostAlias = proposed.hostAlias
            publicIP = proposed.publicIP
            baseDomain = proposed.baseDomain
            applyHarnessSettings(proposed)
        }

        fillFromDetected()
    }

    /// Whatever the CLI already told the app (`AppModel.detected`, read at
    /// launch) fills in for what would otherwise be a blank, required field —
    /// Setup should have little or nothing left to type. A field that already
    /// carries a value, typed or previously saved, is left alone.
    private func fillFromDetected() {
        let detected = model.detected
        if opsRepoPath.isEmpty, let path = detected.opsRepoPath { opsRepoPath = path }
        if publicIP.isEmpty, let ip = detected.publicIP { publicIP = ip }
        if baseDomain.isEmpty, let domain = detected.baseDomain { baseDomain = domain }
    }

    /// Whether a Connection field's current value is exactly what the CLI
    /// detected — Setup shows that as a hint instead of asking the person to
    /// re-type it, with an option to type something else instead.
    private func isDetected(_ field: SettingsIssue.Field) -> Bool {
        switch field {
        case .opsRepoPath: return !opsRepoPath.isEmpty && opsRepoPath == model.detected.opsRepoPath
        case .publicIP: return !publicIP.isEmpty && publicIP == model.detected.publicIP
        case .baseDomain: return !baseDomain.isEmpty && baseDomain == model.detected.baseDomain
        case .hostAlias: return false
        }
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
        // The CLI's folder is hidden (`~/.config/…`): never make the person
        // find a dot-folder in a panel that hides them.
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: opsRepoPath.isEmpty ? NSHomeDirectory() : opsRepoPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        opsRepoPath = url.path
    }

    private func save() {
        let settingsDraft = SettingsDraft(value: draft)
        let value = settingsDraft.committedValue
        if value.debugLogging { PaneLog.prepare() }
        settingsStore.commit(settingsDraft)
        rememberCustomDefaults(value)
        model.settings = value
        model.activePage = nil
        // Before reloading: the panes of a workspace you just hid have to go
        // now, and the reload must not bring their poll back.
        model.applyHiddenWorkspaces()
        model.loadWorkspaces()
    }
}
