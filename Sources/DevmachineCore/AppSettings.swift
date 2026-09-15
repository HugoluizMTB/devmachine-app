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

    public init(
        opsRepoPath: String,
        hostAlias: String,
        publicIP: String,
        baseDomain: String,
        wallpaper: WallpaperChoice = .bundled,
        terminalOpacity: Double = Appearance.defaultTerminalOpacity,
        terminalFontSize: Double = Appearance.defaultTerminalFontSize,
        uiFontScale: Double = Appearance.defaultUIFontScale
    ) {
        self.opsRepoPath = opsRepoPath
        self.hostAlias = hostAlias
        self.publicIP = publicIP
        self.baseDomain = baseDomain
        self.wallpaper = wallpaper
        self.terminalOpacity = Appearance.clampTerminalOpacity(terminalOpacity)
        self.terminalFontSize = Appearance.clampTerminalFontSize(terminalFontSize)
        self.uiFontScale = Appearance.clampUIFontScale(uiFontScale)
    }

    private enum CodingKeys: String, CodingKey {
        case opsRepoPath, hostAlias, publicIP, baseDomain, wallpaper
        case terminalOpacity, terminalFontSize, uiFontScale
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
