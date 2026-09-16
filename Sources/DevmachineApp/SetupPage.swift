import SwiftUI
import AppKit
import DevmachineCore

struct SetupPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var wallpapers: WallpaperStore

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
            hiddenWorkspaces: hiddenWorkspaces
        )
    }

    private var issues: [SettingsIssue] { AppSettings.validate(draft) }

    private var isFirstRun: Bool { !settingsStore.isConfigured }

    var body: some View {
        ZStack {
            WallpaperBackground(style: .photo, choice: wallpaper)
            // The wallpaper grid can outgrow a 560pt window; scroll only then.
            ViewThatFits(in: .vertical) {
                cardBox
                ScrollView(.vertical) { cardBox }
                    .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear { load() }
    }

    private var cardBox: some View {
        card
            .frame(maxWidth: 480)
            .padding(24)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isFirstRun ? "Welcome" : "Settings")
                    .font(.dm(26, weight: .semibold))
                    .foregroundStyle(.white)
                Text("The app talks to one host through ssh and keeps its ops repo on this Mac. Tell it where both are.")
                    .font(.dm(12.5))
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

            workspacesBlock
            wallpaperBlock
            appearanceBlock

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
        if !model.workspaces.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Workspaces")
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

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
                        Text(workspace.name)
                            .font(.dm(12))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                Text(verbatim: "A workspace turned off leaves the sidebar, and "
                    + "the app stops reaching its host: no ssh, no mosh, no "
                    + "poll. Its sessions keep running on the host and come "
                    + "back the moment you turn it on again. This Mac cannot "
                    + "be turned off.")
                    .font(.dm(10))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appearanceBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Appearance")
                .font(.dm(11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

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
                title: "App font size",
                value: $uiFontScale,
                range: Appearance.uiFontScaleRange,
                step: 0.05,
                reading: "\(Int((uiFontScale * 100).rounded()))%"
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
            Toggle(isOn: $debugLogging) {
                Text(verbatim: "Debug logging")
                    .font(.dm(12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Text(verbatim: "Writes what happens around a terminal — the size a "
                + "program is given, when it starts, when a pane is put away and "
                + "brought back — to ~/.devmachine-app/terminal.log. Turn it on "
                + "only while chasing something; off, nothing is written. The "
                + "file keeps itself under a megabyte.")
                .font(.dm(10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: "A session you are not looking at stays connected, "
                + "so switching back to it is instant. Each one costs a client "
                + "process and its scrollback. Past this many, the one left "
                + "alone the longest is disconnected; the session on the other "
                + "side keeps running and reconnects when you return. Keep it "
                + "above your number of workspaces.")
                .font(.dm(10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
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
        VStack(alignment: .leading, spacing: 8) {
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
        if value.debugLogging { PaneLog.prepare() }
        settingsStore.settings = value
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
