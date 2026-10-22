import Foundation

/// Something Settings says that does not block Save: the setup is fine,
/// there is just nothing to reach yet.
public struct SettingsNotice: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The CLI's own folder before `devmachine setup` wrote `config.yml`.
        case noMachineYet
    }

    public let kind: Kind
    public let field: SettingsIssue.Field
    public let message: String

    public init(kind: Kind, field: SettingsIssue.Field, message: String) {
        self.kind = kind
        self.field = field
        self.message = message
    }
}

public struct SettingsIssue: Equatable, Sendable {
    public enum Field: String, Sendable, CaseIterable {
        case opsRepoPath
        case hostAlias
        case publicIP
        case baseDomain
    }

    /// What the app itself can do about it, shown as a button beside the
    /// message. Nil when only the person can fix it (a typo in a field).
    public enum Remedy: Equatable, Sendable {
        /// No CLI on this Mac: the setup flow installs it.
        case installCLI
        /// The CLI is there but `devmachine setup` never ran.
        case runSetup
    }

    public let field: Field
    public let message: String
    public let remedy: Remedy?

    public init(field: Field, message: String, remedy: Remedy? = nil) {
        self.field = field
        self.message = message
        self.remedy = remedy
    }
}

/// What a session runs when it is created. A shell is a shell; the other one
/// starts the agent in it, so a new session is already a conversation.
public enum NewSessionProgram: String, Codable, Sendable, CaseIterable {
    case shell
    case claude

    public var title: String {
        switch self {
        case .shell: return "Normal terminal"
        case .claude: return "Claude Code session"
        }
    }

    /// The line typed into a fresh session, or nothing for a plain shell. It is
    /// typed into the shell rather than run as the session's own command, so
    /// the session outlives the agent: quitting Claude leaves a shell, not a
    /// dead pane.
    public var startupLine: String? {
        switch self {
        case .shell: return nil
        case .claude: return "claude"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var opsRepoPath: String
    public var hostAlias: String
    public var publicIP: String
    public var baseDomain: String
    /// An ssh agent socket to use instead of the 1Password default. Empty
    /// means "figure it out": the 1Password socket if it exists, else
    /// whatever `SSH_AUTH_SOCK` this process inherited.
    public var sshAgentSocket: String
    public var wallpaper: WallpaperChoice
    /// How much of the wallpaper shows through a terminal, from `Appearance`.
    public var terminalOpacity: Double
    public var terminalFontSize: Double
    /// Multiplies every size in the app's own interface.
    public var uiFontScale: Double
    /// Terminals kept connected in the background.
    public var keptTerminals: Int
    /// Writes what happens around a terminal pane to a file. Off by default.
    public var debugLogging: Bool
    /// How a remote pane reaches its machine: mosh when it gets through,
    /// ssh otherwise, unless one of them is forced.
    public var remoteTerminalMode: RemoteTerminalMode
    /// A mouse selection in a terminal goes to the clipboard as soon as the
    /// button is released, as iTerm's "copy on select" does.
    public var copyOnSelect: Bool
    /// A session running a known harness shows that harness's icon before
    /// its name in the sidebar. Off by default: the sidebar stays as it was.
    public var showsHarnessIcons: Bool
    public var showsBusySpinner: Bool
    public var showsBranch: Bool
    public var showsSessionAge: Bool
    public var showsAttention: Bool
    /// How those icons are drawn: in the harness's brand colors, or in the
    /// row's own tint.
    public var harnessIconStyle: HarnessIconStyle
    /// A strip above the terminal with the sessions opened and the files
    /// looked at this run. Off by default: the centre stays as it was.
    public var showsSessionTabs: Bool
    /// Workspaces left out of the sidebar, by ssh alias. A list of what to
    /// hide, not of what to show: a workspace added to `~/.ssh/config` later
    /// appears on its own, which is what you want from a machine that gains
    /// contexts over time.
    public var hiddenWorkspaces: [String]
    public var autoConnectWorkspaces: [String]
    /// Workspace name → its ssh `Host` alias, as `devmachine aliases` reports
    /// it. Refreshed from the CLI on every launch and workspace load; a
    /// workspace missing from it falls back to `workspaceSuffix` guessing.
    public var workspaceAliases: [String: String]
    /// What a session created from the app starts with.
    public var enabledHarnesses: [HarnessID] {
        didSet {
            normalizeSessionPrograms()
        }
    }
    public var localSessionProgram: SessionLaunchChoice {
        didSet {
            localSessionProgram = normalized(localSessionProgram)
        }
    }
    public var remoteSessionProgram: SessionLaunchChoice {
        didSet {
            remoteSessionProgram = normalized(remoteSessionProgram)
        }
    }
    public var workspaceSessionPrograms: [String: SessionLaunchChoice] {
        didSet {
            workspaceSessionPrograms = workspaceSessionPrograms.mapValues(normalized)
        }
    }

    /// Where previews and links from the context panel open.
    public var linkOpening: LinkOpening

    /// What the Operator session starts. Nil until the first open asks, which
    /// is what makes it the first. Not limited to the harnesses turned on: the
    /// chooser offers every harness whose CLI is on this Mac.
    public var operatorProgram: SessionLaunchChoice?
    /// The Operator session in the sidebar and ⌘K. Off hides it; a shell it
    /// already runs keeps running.
    public var operatorSessionEnabled: Bool
    public var chats: ChatSettings

    public var newSessionProgram: NewSessionProgram {
        get {
            localSessionProgram == .harness(.claude) && remoteSessionProgram == .harness(.claude)
                ? .claude
                : .shell
        }
        set {
            let choice: SessionLaunchChoice = newValue == .claude ? .harness(.claude) : .terminal
            enabledHarnesses = [.claude]
            localSessionProgram = choice
            remoteSessionProgram = choice
        }
    }

    public init(
        opsRepoPath: String,
        hostAlias: String,
        publicIP: String,
        baseDomain: String,
        sshAgentSocket: String = "",
        wallpaper: WallpaperChoice = .bundled,
        terminalOpacity: Double = Appearance.defaultTerminalOpacity,
        terminalFontSize: Double = Appearance.defaultTerminalFontSize,
        uiFontScale: Double = Appearance.defaultUIFontScale,
        keptTerminals: Int = Appearance.defaultKeptTerminals,
        debugLogging: Bool = false,
        remoteTerminalMode: RemoteTerminalMode = .automatic,
        copyOnSelect: Bool = true,
        showsHarnessIcons: Bool = false,
        showsBusySpinner: Bool = true,
        showsBranch: Bool = true,
        showsSessionAge: Bool = true,
        showsAttention: Bool = true,
        harnessIconStyle: HarnessIconStyle = .color,
        showsSessionTabs: Bool = false,
        hiddenWorkspaces: [String] = [],
        autoConnectWorkspaces: [String] = [],
        workspaceAliases: [String: String] = [:],
        enabledHarnesses: [HarnessID] = [.claude],
        localSessionProgram: SessionLaunchChoice = .terminal,
        remoteSessionProgram: SessionLaunchChoice = .terminal,
        workspaceSessionPrograms: [String: SessionLaunchChoice] = [:],
        linkOpening: LinkOpening = .defaultBrowser,
        operatorProgram: SessionLaunchChoice? = nil,
        operatorSessionEnabled: Bool = true,
        chats: ChatSettings = .default,
        newSessionProgram: NewSessionProgram? = nil
    ) {
        self.opsRepoPath = opsRepoPath
        self.hostAlias = hostAlias
        self.publicIP = publicIP
        self.baseDomain = baseDomain
        self.sshAgentSocket = sshAgentSocket
        self.wallpaper = wallpaper
        self.terminalOpacity = Appearance.clampTerminalOpacity(terminalOpacity)
        self.terminalFontSize = Appearance.clampTerminalFontSize(terminalFontSize)
        self.uiFontScale = Appearance.clampUIFontScale(uiFontScale)
        self.keptTerminals = Appearance.clampKeptTerminals(keptTerminals)
        self.debugLogging = debugLogging
        self.remoteTerminalMode = remoteTerminalMode
        self.copyOnSelect = copyOnSelect
        self.showsHarnessIcons = showsHarnessIcons
        self.showsBusySpinner = showsBusySpinner
        self.showsBranch = showsBranch
        self.showsSessionAge = showsSessionAge
        self.showsAttention = showsAttention
        self.harnessIconStyle = harnessIconStyle
        self.showsSessionTabs = showsSessionTabs
        self.hiddenWorkspaces = hiddenWorkspaces
        self.autoConnectWorkspaces = autoConnectWorkspaces
        self.workspaceAliases = workspaceAliases
        self.enabledHarnesses = enabledHarnesses
        self.localSessionProgram = localSessionProgram
        self.remoteSessionProgram = remoteSessionProgram
        self.workspaceSessionPrograms = workspaceSessionPrograms
        self.linkOpening = linkOpening
        self.operatorProgram = operatorProgram
        self.operatorSessionEnabled = operatorSessionEnabled
        self.chats = chats

        if let newSessionProgram {
            let choice: SessionLaunchChoice = newSessionProgram == .claude ? .harness(.claude) : .terminal
            self.enabledHarnesses = [.claude]
            self.localSessionProgram = choice
            self.remoteSessionProgram = choice
        }

        normalizeSessionPrograms()
    }

    private enum CodingKeys: String, CodingKey {
        case opsRepoPath, hostAlias, publicIP, baseDomain, sshAgentSocket, wallpaper
        case terminalOpacity, terminalFontSize, uiFontScale, keptTerminals, debugLogging, remoteTerminalMode
        case copyOnSelect, showsHarnessIcons, harnessIconStyle, showsSessionTabs
        case showsBusySpinner, showsBranch, showsSessionAge, showsAttention
        case hiddenWorkspaces, autoConnectWorkspaces, workspaceAliases, enabledHarnesses, localSessionProgram, remoteSessionProgram
        case workspaceSessionPrograms, newSessionProgram, linkOpening
        case operatorProgram, operatorSessionEnabled, chats
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        opsRepoPath = try values.decode(String.self, forKey: .opsRepoPath)
        hostAlias = try values.decode(String.self, forKey: .hostAlias)
        publicIP = try values.decode(String.self, forKey: .publicIP)
        baseDomain = try values.decode(String.self, forKey: .baseDomain)
        // Settings written before this existed decode to "figure it out".
        sshAgentSocket = try values.decodeIfPresent(String.self, forKey: .sshAgentSocket) ?? ""
        wallpaper = try values.decodeIfPresent(WallpaperChoice.self, forKey: .wallpaper) ?? .bundled
        // Settings written before these existed decode to the defaults.
        terminalOpacity = Appearance.clampTerminalOpacity(
            try values.decodeIfPresent(Double.self, forKey: .terminalOpacity)
                ?? Appearance.defaultTerminalOpacity)
        terminalFontSize = Appearance.clampTerminalFontSize(
            try values.decodeIfPresent(Double.self, forKey: .terminalFontSize)
                ?? Appearance.defaultTerminalFontSize)
        uiFontScale = Appearance.clampUIFontScale(
            try values.decodeIfPresent(Double.self, forKey: .uiFontScale)
                ?? Appearance.defaultUIFontScale)
        keptTerminals = Appearance.clampKeptTerminals(
            try values.decodeIfPresent(Int.self, forKey: .keptTerminals)
                ?? Appearance.defaultKeptTerminals)
        debugLogging = try values.decodeIfPresent(Bool.self, forKey: .debugLogging) ?? false
        remoteTerminalMode =
            try values.decodeIfPresent(RemoteTerminalMode.self, forKey: .remoteTerminalMode) ?? .automatic
        copyOnSelect = try values.decodeIfPresent(Bool.self, forKey: .copyOnSelect) ?? true
        showsHarnessIcons = try values.decodeIfPresent(Bool.self, forKey: .showsHarnessIcons) ?? false
        showsBusySpinner = try values.decodeIfPresent(Bool.self, forKey: .showsBusySpinner) ?? true
        showsBranch = try values.decodeIfPresent(Bool.self, forKey: .showsBranch) ?? true
        showsSessionAge = try values.decodeIfPresent(Bool.self, forKey: .showsSessionAge) ?? true
        showsAttention = try values.decodeIfPresent(Bool.self, forKey: .showsAttention) ?? true
        harnessIconStyle = (try? values.decodeIfPresent(HarnessIconStyle.self, forKey: .harnessIconStyle)) ?? .color
        showsSessionTabs = try values.decodeIfPresent(Bool.self, forKey: .showsSessionTabs) ?? false
        linkOpening = (try? values.decodeIfPresent(LinkOpening.self, forKey: .linkOpening)) ?? .defaultBrowser
        operatorProgram = try? values.decodeIfPresent(SessionLaunchChoice.self, forKey: .operatorProgram)
        operatorSessionEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .operatorSessionEnabled)) ?? true
        chats = (try? values.decodeIfPresent(ChatSettings.self, forKey: .chats)) ?? .default
        hiddenWorkspaces =
            try values.decodeIfPresent([String].self, forKey: .hiddenWorkspaces) ?? []
        autoConnectWorkspaces = try values.decodeIfPresent([String].self, forKey: .autoConnectWorkspaces) ?? []
        // Settings written before this existed decode to "nothing detected yet".
        workspaceAliases =
            try values.decodeIfPresent([String: String].self, forKey: .workspaceAliases) ?? [:]
        let enabledHarnesses = try values.decodeIfPresent([HarnessID].self, forKey: .enabledHarnesses)
        let localSessionProgram = try values.decodeIfPresent(SessionLaunchChoice.self, forKey: .localSessionProgram)
        let remoteSessionProgram = try values.decodeIfPresent(SessionLaunchChoice.self, forKey: .remoteSessionProgram)
        let workspaceSessionPrograms = try values.decodeIfPresent(
            [String: SessionLaunchChoice].self,
            forKey: .workspaceSessionPrograms
        )

        if enabledHarnesses == nil,
           localSessionProgram == nil,
           remoteSessionProgram == nil,
           workspaceSessionPrograms == nil {
            let legacyProgram =
                try values.decodeIfPresent(NewSessionProgram.self, forKey: .newSessionProgram) ?? .shell
            let choice: SessionLaunchChoice = legacyProgram == .claude ? .harness(.claude) : .terminal
            self.enabledHarnesses = [.claude]
            self.localSessionProgram = choice
            self.remoteSessionProgram = choice
            self.workspaceSessionPrograms = [:]
        } else {
            self.enabledHarnesses = enabledHarnesses ?? [.claude]
            self.localSessionProgram = localSessionProgram ?? .terminal
            self.remoteSessionProgram = remoteSessionProgram ?? .terminal
            self.workspaceSessionPrograms = workspaceSessionPrograms ?? [:]
        }

        normalizeSessionPrograms()
    }

    public func sessionProgram(for workspace: String) -> SessionLaunchChoice {
        normalized(workspaceSessionPrograms[workspace] ?? remoteSessionProgram)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(opsRepoPath, forKey: .opsRepoPath)
        try values.encode(hostAlias, forKey: .hostAlias)
        try values.encode(publicIP, forKey: .publicIP)
        try values.encode(baseDomain, forKey: .baseDomain)
        try values.encode(sshAgentSocket, forKey: .sshAgentSocket)
        try values.encode(wallpaper, forKey: .wallpaper)
        try values.encode(terminalOpacity, forKey: .terminalOpacity)
        try values.encode(terminalFontSize, forKey: .terminalFontSize)
        try values.encode(uiFontScale, forKey: .uiFontScale)
        try values.encode(keptTerminals, forKey: .keptTerminals)
        try values.encode(debugLogging, forKey: .debugLogging)
        try values.encode(remoteTerminalMode, forKey: .remoteTerminalMode)
        try values.encode(copyOnSelect, forKey: .copyOnSelect)
        try values.encode(showsHarnessIcons, forKey: .showsHarnessIcons)
        try values.encode(showsBusySpinner, forKey: .showsBusySpinner)
        try values.encode(showsBranch, forKey: .showsBranch)
        try values.encode(showsSessionAge, forKey: .showsSessionAge)
        try values.encode(showsAttention, forKey: .showsAttention)
        try values.encode(harnessIconStyle, forKey: .harnessIconStyle)
        try values.encode(showsSessionTabs, forKey: .showsSessionTabs)
        try values.encode(hiddenWorkspaces, forKey: .hiddenWorkspaces)
        try values.encode(autoConnectWorkspaces, forKey: .autoConnectWorkspaces)
        try values.encode(workspaceAliases, forKey: .workspaceAliases)
        try values.encode(enabledHarnesses, forKey: .enabledHarnesses)
        try values.encode(localSessionProgram, forKey: .localSessionProgram)
        try values.encode(remoteSessionProgram, forKey: .remoteSessionProgram)
        try values.encode(workspaceSessionPrograms, forKey: .workspaceSessionPrograms)
        try values.encode(linkOpening, forKey: .linkOpening)
        try values.encodeIfPresent(operatorProgram, forKey: .operatorProgram)
        try values.encode(operatorSessionEnabled, forKey: .operatorSessionEnabled)
        try values.encode(chats, forKey: .chats)
    }

    private func normalized(_ choice: SessionLaunchChoice) -> SessionLaunchChoice {
        switch choice {
        case .terminal:
            return .terminal
        case let .harness(harness):
            return enabledHarnesses.contains(harness) ? choice : .terminal
        case let .custom(raw):
            return CustomSessionCommand.normalized(raw).map(SessionLaunchChoice.custom) ?? .terminal
        }
    }

    private mutating func normalizeSessionPrograms() {
        localSessionProgram = normalized(localSessionProgram)
        remoteSessionProgram = normalized(remoteSessionProgram)
        workspaceSessionPrograms = workspaceSessionPrograms.mapValues(normalized)
    }

    public static let empty = AppSettings(opsRepoPath: "", hostAlias: "", publicIP: "", baseDomain: "")

    /// `devmachine aliases --write` always names a workspace's Host entry
    /// `<workspace>-devmachine` — the suffix is fixed by the CLI, not by
    /// this field. An empty alias falls back to that fixed name instead of
    /// producing a bare `-`, which would match no real ssh alias and break
    /// every workspace session (open, list, kill).
    public var workspaceSuffix: String { "-" + (hostAlias.isEmpty ? "devmachine" : hostAlias) }

    /// A workspace's ssh `Host` alias: what `devmachine aliases` reported for
    /// it, or the guessed suffix when that has not been read yet (offline
    /// launch, or a CLI too old to have the command).
    public func hostAlias(forWorkspace workspace: String) -> String {
        workspaceAliases[workspace] ?? workspace + workspaceSuffix
    }

    /// The reverse of `hostAlias(forWorkspace:)` — an ssh alias back to the
    /// workspace name it belongs to, for a command that only carries the
    /// alias (a session's `CommandTarget`). Falls back to stripping the
    /// guessed suffix when the alias is not in the detected map.
    public func workspaceName(forAlias alias: String) -> String {
        if let name = workspaceAliases.first(where: { $0.value == alias })?.key {
            return name
        }
        let suffix = workspaceSuffix
        return alias.hasSuffix(suffix) ? String(alias.dropLast(suffix.count)) : alias
    }

    public static let aliasPattern = "^[A-Za-z0-9._-]+$"
    public static let ipv4Pattern =
        "^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$"
    public static let domainPattern = "^[a-z0-9-]+(\\.[a-z0-9-]+)+$"

    public static let opsRepoMarker = "config.yml"

    /// The folder `validate` lets through before a machine exists still
    /// needs a way forward, or a fresh Mac lands on a silent Settings page.
    public static func notices(
        _ settings: AppSettings,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        cliExecutableFound: Bool = true,
        cliConfigDirectory: String? = nil
    ) -> [SettingsNotice] {
        guard cliExecutableFound, !settings.opsRepoPath.isEmpty,
              settings.opsRepoPath == cliConfigDirectory,
              !fileExists(settings.opsRepoPath + "/" + opsRepoMarker)
        else { return [] }
        return [SettingsNotice(
            kind: .noMachineYet, field: .opsRepoPath,
            message: "No machine yet. Run the setup to connect a server, or add a machine.")]
    }

    public static func validate(
        _ settings: AppSettings,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        cliExecutableFound: Bool = true,
        cliConfigDirectory: String? = nil
    ) -> [SettingsIssue] {
        var issues: [SettingsIssue] = []

        // The CLI's own folder is only written with the first machine, so a
        // person with no machine yet can still start the app and add one.
        let isCLIFolder = settings.opsRepoPath == cliConfigDirectory
        // Without the CLI the folder is missing too, and that is not a second
        // problem: one issue, naming the one fix.
        if !cliExecutableFound {
            issues.append(SettingsIssue(
                field: .opsRepoPath,
                message: "The devmachine CLI is not installed on this Mac. Run the setup, or install it in a "
                    + "terminal: \(CLIInstallPlan.noHomebrewCommand)",
                remedy: .installCLI))
        } else if settings.opsRepoPath.isEmpty {
            issues.append(SettingsIssue(field: .opsRepoPath, message: "Choose the devmachine configuration folder."))
        } else if !isCLIFolder, !fileExists(settings.opsRepoPath) {
            issues.append(SettingsIssue(
                field: .opsRepoPath,
                message: "devmachine setup has not run yet: this folder does not exist.",
                remedy: .runSetup))
        } else if !isCLIFolder, !fileExists(settings.opsRepoPath + "/" + opsRepoMarker) {
            issues.append(SettingsIssue(
                field: .opsRepoPath,
                message: "devmachine setup has not run yet: there is no \(opsRepoMarker) in this folder.",
                remedy: .runSetup))
        }

        // The host alias and the public IP are no longer shown in Settings, so a
        // stale value there must never block saving.
        if !settings.baseDomain.isEmpty, !matches(settings.baseDomain, domainPattern) {
            issues.append(SettingsIssue(field: .baseDomain, message: "Type a lowercase domain, like example.com."))
        }

        return issues
    }

    public static func prefill(
        sshConfig: String,
        sshResolve: (String) -> String?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> AppSettings {
        let alias = SSHConfigParser.hostTokens(sshConfig).contains("devmachine") ? "devmachine" : ""
        let repoPath = NSHomeDirectory() + "/.config/devmachine"

        return AppSettings(
            opsRepoPath: fileExists(repoPath + "/" + opsRepoMarker) ? repoPath : "",
            hostAlias: alias,
            publicIP: alias.isEmpty ? "" : resolveIPv4(alias: alias, sshResolve: sshResolve),
            baseDomain: ""
        )
    }

    // `ssh -G` answers with the alias itself when the host has no entry, so only
    // an address shaped like an IPv4 counts as resolved.
    private static func resolveIPv4(alias: String, sshResolve: (String) -> String?) -> String {
        for candidate in ["\(alias)-pub", alias] {
            if let value = sshResolve(candidate), matches(value, ipv4Pattern) {
                return value
            }
        }
        return ""
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
