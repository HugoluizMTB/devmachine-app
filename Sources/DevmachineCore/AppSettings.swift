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
    /// Workspaces left out of the sidebar, by ssh alias. A list of what to
    /// hide, not of what to show: a workspace added to `~/.ssh/config` later
    /// appears on its own, which is what you want from a machine that gains
    /// contexts over time.
    public var hiddenWorkspaces: [String]
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
        wallpaper: WallpaperChoice = .bundled,
        terminalOpacity: Double = Appearance.defaultTerminalOpacity,
        terminalFontSize: Double = Appearance.defaultTerminalFontSize,
        uiFontScale: Double = Appearance.defaultUIFontScale,
        keptTerminals: Int = Appearance.defaultKeptTerminals,
        debugLogging: Bool = false,
        hiddenWorkspaces: [String] = [],
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
        self.wallpaper = wallpaper
        self.terminalOpacity = Appearance.clampTerminalOpacity(terminalOpacity)
        self.terminalFontSize = Appearance.clampTerminalFontSize(terminalFontSize)
        self.uiFontScale = Appearance.clampUIFontScale(uiFontScale)
        self.keptTerminals = Appearance.clampKeptTerminals(keptTerminals)
        self.debugLogging = debugLogging
        self.hiddenWorkspaces = hiddenWorkspaces
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
        case opsRepoPath, hostAlias, publicIP, baseDomain, wallpaper
        case terminalOpacity, terminalFontSize, uiFontScale, keptTerminals, debugLogging
        case hiddenWorkspaces, enabledHarnesses, localSessionProgram, remoteSessionProgram
        case workspaceSessionPrograms, newSessionProgram
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        opsRepoPath = try values.decode(String.self, forKey: .opsRepoPath)
        hostAlias = try values.decode(String.self, forKey: .hostAlias)
        publicIP = try values.decode(String.self, forKey: .publicIP)
        baseDomain = try values.decode(String.self, forKey: .baseDomain)
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
        hiddenWorkspaces =
            try values.decodeIfPresent([String].self, forKey: .hiddenWorkspaces) ?? []
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
        try values.encode(wallpaper, forKey: .wallpaper)
        try values.encode(terminalOpacity, forKey: .terminalOpacity)
        try values.encode(terminalFontSize, forKey: .terminalFontSize)
        try values.encode(uiFontScale, forKey: .uiFontScale)
        try values.encode(keptTerminals, forKey: .keptTerminals)
        try values.encode(debugLogging, forKey: .debugLogging)
        try values.encode(hiddenWorkspaces, forKey: .hiddenWorkspaces)
        try values.encode(enabledHarnesses, forKey: .enabledHarnesses)
        try values.encode(localSessionProgram, forKey: .localSessionProgram)
        try values.encode(remoteSessionProgram, forKey: .remoteSessionProgram)
        try values.encode(workspaceSessionPrograms, forKey: .workspaceSessionPrograms)
    }

    private func normalized(_ choice: SessionLaunchChoice) -> SessionLaunchChoice {
        guard case let .harness(harness) = choice, !enabledHarnesses.contains(harness) else {
            return choice
        }
        return .terminal
    }

    private mutating func normalizeSessionPrograms() {
        localSessionProgram = normalized(localSessionProgram)
        remoteSessionProgram = normalized(remoteSessionProgram)
        workspaceSessionPrograms = workspaceSessionPrograms.mapValues(normalized)
    }

    public static let empty = AppSettings(opsRepoPath: "", hostAlias: "", publicIP: "", baseDomain: "")

    public var workspaceSuffix: String { "-" + hostAlias }

    public static let aliasPattern = "^[A-Za-z0-9._-]+$"
    public static let ipv4Pattern =
        "^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$"
    public static let domainPattern = "^[a-z0-9-]+(\\.[a-z0-9-]+)+$"

    public static let opsRepoMarker = "ansible/site.yml"

    public static func validate(
        _ settings: AppSettings,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [SettingsIssue] {
        var issues: [SettingsIssue] = []

        if settings.opsRepoPath.isEmpty {
            issues.append(SettingsIssue(field: .opsRepoPath, message: "Choose the folder of the ops repo."))
        } else if !fileExists(settings.opsRepoPath) {
            issues.append(SettingsIssue(field: .opsRepoPath, message: "This folder does not exist."))
        } else if !fileExists(settings.opsRepoPath + "/" + opsRepoMarker) {
            issues.append(SettingsIssue(field: .opsRepoPath, message: "No \(opsRepoMarker) in this folder."))
        }

        if settings.hostAlias.isEmpty {
            issues.append(SettingsIssue(field: .hostAlias, message: "Type the ssh alias of the host."))
        } else if !matches(settings.hostAlias, aliasPattern) {
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
        let repoPath = NSHomeDirectory() + "/dev/devmachine"

        return AppSettings(
            opsRepoPath: fileExists(repoPath) ? repoPath : "",
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
