import Foundation

public struct SettingsIssue: Equatable, Sendable {
    public enum Field: String, Sendable, CaseIterable {
        case opsRepoPath
        case hostAlias
        case publicIP
        case baseDomain
    }

    public let field: Field
    public let message: String

    public init(field: Field, message: String) {
        self.field = field
        self.message = message
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
    /// Workspaces left out of the sidebar, by ssh alias. A list of what to
    /// hide, not of what to show: a workspace added to `~/.ssh/config` later
    /// appears on its own, which is what you want from a machine that gains
    /// contexts over time.
    public var hiddenWorkspaces: [String]
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
        hiddenWorkspaces: [String] = [],
        workspaceAliases: [String: String] = [:],
        enabledHarnesses: [HarnessID] = [.claude],
        localSessionProgram: SessionLaunchChoice = .terminal,
        remoteSessionProgram: SessionLaunchChoice = .terminal,
        workspaceSessionPrograms: [String: SessionLaunchChoice] = [:],
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
        self.hiddenWorkspaces = hiddenWorkspaces
        self.workspaceAliases = workspaceAliases
        self.enabledHarnesses = enabledHarnesses
        self.localSessionProgram = localSessionProgram
        self.remoteSessionProgram = remoteSessionProgram
        self.workspaceSessionPrograms = workspaceSessionPrograms

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
        case copyOnSelect
        case hiddenWorkspaces, workspaceAliases, enabledHarnesses, localSessionProgram, remoteSessionProgram
        case workspaceSessionPrograms, newSessionProgram
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
        hiddenWorkspaces =
            try values.decodeIfPresent([String].self, forKey: .hiddenWorkspaces) ?? []
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
        try values.encode(hiddenWorkspaces, forKey: .hiddenWorkspaces)
        try values.encode(workspaceAliases, forKey: .workspaceAliases)
        try values.encode(enabledHarnesses, forKey: .enabledHarnesses)
        try values.encode(localSessionProgram, forKey: .localSessionProgram)
        try values.encode(remoteSessionProgram, forKey: .remoteSessionProgram)
        try values.encode(workspaceSessionPrograms, forKey: .workspaceSessionPrograms)
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

    /// What to do next, once the folder or the CLI itself turns out to be
    /// missing — the same fix both times, so the same line names it.
    public static let cliInstallHint =
        "Install the CLI (brew install mydevmachine/tap/devmachine), run "
        + "devmachine setup in a terminal, then come back."

    public static func validate(
        _ settings: AppSettings,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        cliExecutableFound: Bool = true
    ) -> [SettingsIssue] {
        var issues: [SettingsIssue] = []

        if settings.opsRepoPath.isEmpty {
            issues.append(SettingsIssue(field: .opsRepoPath, message: "Choose the devmachine configuration folder."))
        } else if !fileExists(settings.opsRepoPath) {
            issues.append(SettingsIssue(
                field: .opsRepoPath, message: "This folder does not exist. \(cliInstallHint)"))
        } else if !fileExists(settings.opsRepoPath + "/" + opsRepoMarker) {
            issues.append(SettingsIssue(
                field: .opsRepoPath, message: "No \(opsRepoMarker) in this folder. \(cliInstallHint)"))
        }

        if !cliExecutableFound {
            issues.append(SettingsIssue(
                field: .opsRepoPath, message: "Devmachine CLI was not found on this Mac. \(cliInstallHint)"))
        }

        // No longer needed for an admin login — every admin command now runs
        // through the devmachine CLI. Left blank, it only means the app
        // cannot match `<workspace>-<alias>` entries in ~/.ssh/config yet.
        if !settings.hostAlias.isEmpty, !matches(settings.hostAlias, aliasPattern) {
            issues.append(SettingsIssue(field: .hostAlias, message: "Only letters, digits, dot, dash and underscore."))
        }

        if !matches(settings.publicIP, ipv4Pattern) {
            issues.append(SettingsIssue(field: .publicIP, message: "Type the public IPv4 of the host."))
        }

        if !matches(settings.baseDomain, domainPattern) {
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
