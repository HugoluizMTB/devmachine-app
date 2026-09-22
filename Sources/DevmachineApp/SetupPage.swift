import SwiftUI
import AppKit
import DevmachineCore

/// The panes of Settings. One column held every field before, which made a
/// change to the font size a scroll past every wallpaper.
enum SettingsSection: String, CaseIterable {
    case connection, workspaces, harnesses, appearance, terminal, advanced

    var title: String {
        switch self {
        case .connection: return "Connection"
        case .workspaces: return "Workspaces"
        case .harnesses: return "Harnesses"
        case .appearance: return "Appearance"
        case .terminal: return "Terminal"
        case .advanced: return "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .connection: return "The host this app talks to, and the ops repo it applies."
        case .workspaces: return "Which workspaces the sidebar shows and the app reaches."
        case .harnesses: return "Choose what new sessions start with."
        case .appearance: return "The wallpaper behind the panes, and the size of the interface."
        case .terminal: return "How a terminal looks, and how many stay connected."
        case .advanced: return "Things to turn on only while chasing a problem."
        }
    }

    var systemImage: String {
        switch self {
        case .connection: return "network"
        case .workspaces: return "square.grid.2x2"
        case .harnesses: return "sparkles"
        case .appearance: return "photo"
        case .terminal: return "terminal"
        case .advanced: return "wrench.and.screwdriver"
        }
    }

    /// Every field that can fail validation lives in Connection, so that is the
    /// pane the rail marks when something is wrong.
    var showsValidation: Bool { self == .connection }
}

private enum LaunchChoiceTag: Hashable {
    case terminal
    case harness(HarnessID)

    init(_ choice: SessionLaunchChoice) {
        switch choice {
        case .terminal:
            self = .terminal
        case let .harness(id):
            self = .harness(id)
        }
    }

    var choice: SessionLaunchChoice {
        switch self {
        case .terminal:
            return .terminal
        case let .harness(id):
            return .harness(id)
        }
    }
}

struct SetupPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var wallpapers: WallpaperStore
    @Environment(\.harnessSettingsFacade) private var harnessSettingsFacade

    /// Not a theme id in the library — the chip that shows the built-in gradients.
    static let gradientTheme = "gradient"

    @State private var opsRepoPath = ""
    @State private var hostAlias = ""
    @State private var publicIP = ""
    @State private var baseDomain = ""
    @State private var wallpaper = WallpaperChoice.bundled
    @State private var themeID = SetupPage.gradientTheme
    @State private var terminalOpacity = Appearance.defaultTerminalOpacity
    @State private var terminalFontSize = Appearance.defaultTerminalFontSize
    @State private var uiFontScale = Appearance.defaultUIFontScale
    @State private var keptTerminals = Appearance.defaultKeptTerminals
    @State private var debugLogging = false
    @State private var hiddenWorkspaces: [String] = []
    @State private var enabledHarnesses = AppSettings.empty.enabledHarnesses
    @State private var localSessionProgram = SessionLaunchChoice.terminal
    @State private var remoteSessionProgram = SessionLaunchChoice.terminal
    @State private var workspaceSessionPrograms: [String: SessionLaunchChoice] = [:]
    @State private var harnessErrors: [HarnessID: String] = [:]

    private var draft: AppSettings {
        AppSettings(
            opsRepoPath: opsRepoPath.trimmingCharacters(in: .whitespaces),
            hostAlias: hostAlias.trimmingCharacters(in: .whitespaces),
            publicIP: publicIP.trimmingCharacters(in: .whitespaces),
            baseDomain: baseDomain.trimmingCharacters(in: .whitespaces),
            wallpaper: wallpaper,
            terminalOpacity: terminalOpacity,
            terminalFontSize: terminalFontSize,
            uiFontScale: uiFontScale,
            keptTerminals: keptTerminals,
            debugLogging: debugLogging,
            hiddenWorkspaces: hiddenWorkspaces,
            enabledHarnesses: enabledHarnesses,
            localSessionProgram: localSessionProgram,
            remoteSessionProgram: remoteSessionProgram,
            workspaceSessionPrograms: workspaceSessionPrograms
        )
    }

    private var issues: [SettingsIssue] { AppSettings.validate(draft) }

    private var isFirstRun: Bool { !settingsStore.isConfigured }

    @State private var section = SettingsSection.connection

    var body: some View {
        ZStack {
            WallpaperBackground(style: .photo, choice: wallpaper)
            card
                .frame(maxWidth: 940, maxHeight: 640)
                .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear { load() }
    }

    private var card: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(Color.white.opacity(0.12))
            VStack(spacing: 0) {
                sectionBody
                Divider().overlay(Color.white.opacity(0.12))
                footer
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
    }

    /// The list of sections. Everything used to be one column, so a change to
    /// the font size meant scrolling past every wallpaper.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isFirstRun ? "Welcome" : "Settings")
                    .font(.dm(18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(isFirstRun ? "Tell the app where the host is." : "Devmachine")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 14)

            ForEach(SettingsSection.allCases, id: \.self) { item in
                railRow(item)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 208)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func railRow(_ item: SettingsSection) -> some View {
        let selected = section == item
        let broken = item.showsValidation && !issues.isEmpty
        return HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.dm(11))
                .frame(width: 16)
                .foregroundStyle(selected ? .white : .white.opacity(0.6))
            Text(item.title)
                .font(.dm(12.5))
                .foregroundStyle(selected ? .white : .white.opacity(0.75))
            Spacer(minLength: 4)
            if broken {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.dm(10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.white.opacity(0.14) : .clear)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { section = item }
    }

    private var sectionBody: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
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
                case .workspaces: workspacesBlock
                case .harnesses: harnessesBlock
                case .appearance: wallpaperBlock
                case .terminal: terminalBlock
                case .advanced: advancedBlock
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let issue = issues.first {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.dm(11))
                    .foregroundStyle(.orange)
                Text(issue.message)
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            if !isFirstRun {
                Button("Cancel") { model.activePage = nil }
                    .keyboardShortcut(.cancelAction)
            }
            Button(isFirstRun ? "Start devmachine" : "Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(!issues.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.regular)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var connectionBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        }
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
                .font(.dm(11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            content()
            if let issue = issues.first(where: { $0.field == field }) {
                Text(issue.message)
                    .font(.dm(11))
                    .foregroundStyle(.orange)
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
    @ViewBuilder
    private var workspacesBlock: some View {
        if model.workspaces.isEmpty {
            note("No workspace yet. They are the ssh aliases ending in "
                + "-\(hostAlias.isEmpty ? "alias" : hostAlias); the app reads them from "
                + "~/.ssh/config once the host above is set.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
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

    private var harnessesBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                settingsHeading("Available harnesses")
                ForEach(harnessSettingsFacade.harnesses) { descriptor in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: harnessEnabledBinding(descriptor.id)) {
                            HStack(spacing: 8) {
                                Image(systemName: descriptor.systemImage)
                                    .font(.dm(10))
                                    .foregroundStyle(descriptor.color)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: descriptor.title)
                                        .font(.dm(12.5, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Text(verbatim: "Make \(descriptor.shortTitle) available for session defaults.")
                                        .font(.dm(10))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        if let message = harnessErrors[descriptor.id] {
                            Text(verbatim: message)
                                .font(.dm(10))
                                .foregroundStyle(.orange)
                                .padding(.leading, 24)
                        }
                    }
                }
                note("Turning a harness on checks only this Mac. The app never "
                    + "installs a CLI or probes a remote workspace.")
            }

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                settingsHeading("Session defaults")
                launchChoicePicker(
                    title: "This Mac",
                    detail: "New local sessions",
                    selection: $localSessionProgram
                )
                launchChoicePicker(
                    title: "Remote fallback",
                    detail: "New workspaces inherit this choice",
                    selection: $remoteSessionProgram
                )

                if model.workspaces.isEmpty {
                    note("Workspace overrides appear after remote workspaces are discovered.")
                } else {
                    ForEach(model.workspaces) { workspace in
                        launchChoicePicker(
                            title: workspace.name,
                            detail: workspace.alias,
                            selection: workspaceChoiceBinding(workspace.alias)
                        )
                        if workspaceSessionPrograms[workspace.alias] != nil {
                            Button("Use remote fallback") {
                                workspaceSessionPrograms.removeValue(forKey: workspace.alias)
                            }
                            .buttonStyle(.plain)
                            .font(.dm(10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }

                note("A harness is typed into the new shell. Leaving it keeps the "
                    + "session open, and sessions that already exist are never touched.")
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
        selection: Binding<SessionLaunchChoice>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.dm(12))
                    .foregroundStyle(.white.opacity(0.85))
                Text(verbatim: detail)
                    .font(.dm(10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 8)
            Picker("", selection: Binding(
                get: { LaunchChoiceTag(selection.wrappedValue) },
                set: { selection.wrappedValue = $0.choice }
            )) {
                ForEach(launchOptions) { option in
                    Text(verbatim: option.title)
                        .tag(LaunchChoiceTag(option.choice))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 170)
        }
    }

    private var launchOptions: [HarnessLaunchOption] {
        SettingsDraft(value: draft).launchOptions(using: harnessSettingsFacade)
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
        case let .cliNotFound(title):
            return "\(title) was not found on this Mac."
        case .harnessNotRegistered:
            return "This harness is not available."
        }
    }

    private var terminalBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        }
    }

    private var advancedBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 2) {
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
        VStack(alignment: .leading, spacing: 14) {
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
        let selected = themeID == id
        return Text(verbatim: title)
            .font(.dm(11, weight: .medium))
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                selected ? Color.white.opacity(0.18) : Color.white.opacity(0.07),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    selected ? Color.accentColor : Color.white.opacity(0.12),
                    lineWidth: selected ? 1 : 0.5
                )
            )
            .contentShape(Capsule())
            .onTapGesture { themeID = id }
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
        .frame(height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(ring(selected: wallpaper == Self.choice(for: photo)))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { select(photo) }
        .onAppear { wallpapers.ensureThumbnail(photo) }
    }

    private func gradientCell(_ gradient: WallpaperGradient) -> some View {
        gradient.swatch
            .frame(height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(verbatim: gradient.title)
                    .font(.dm(10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(6)
            }
            .overlay(ring(selected: wallpaper == .gradient(name: gradient.name)))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture { wallpaper = .gradient(name: gradient.name) }
    }

    private func ring(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
                selected ? Color.accentColor : Color.white.opacity(0.12),
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
            terminalOpacity = current.terminalOpacity
            terminalFontSize = current.terminalFontSize
            uiFontScale = current.uiFontScale
            keptTerminals = current.keptTerminals
            debugLogging = current.debugLogging
            hiddenWorkspaces = current.hiddenWorkspaces
            applyHarnessSettings(current)
            return
        }

        let configPath = NSHomeDirectory() + "/.ssh/config"
        let config = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        let proposed = AppSettings.prefill(sshConfig: config, sshResolve: Self.resolveHostname)
        opsRepoPath = proposed.opsRepoPath
        hostAlias = proposed.hostAlias
        publicIP = proposed.publicIP
        baseDomain = proposed.baseDomain
        applyHarnessSettings(proposed)
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
        let settingsDraft = SettingsDraft(value: draft)
        let value = settingsDraft.committedValue
        if value.debugLogging { PaneLog.prepare() }
        settingsStore.commit(settingsDraft)
        model.settings = value
        model.activePage = nil
        // Before reloading: the panes of a workspace you just hid have to go
        // now, and the reload must not bring their poll back.
        model.applyHiddenWorkspaces()
        model.loadWorkspaces()
    }
}

private extension View {
    func setupField() -> some View {
        self
            .font(.dm(13))
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
