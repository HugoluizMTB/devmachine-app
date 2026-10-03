import Foundation

/// CLI 0.7.29 reports what the Workspaces page used to guess: the
/// configured `defaults.workspace` and top-level login answers (`config
/// show`), each package's declared variables (`packages list`) and each
/// workspace's own login answers (`workspaces list`). An older CLI keeps
/// the fallbacks: the setup's default packages, free-text settings, and no
/// login sharing on the page.
public enum WorkspaceJSON {
    public static let minimumCLIVersion = SemanticVersion(major: 0, minor: 7, patch: 29)

    public static func isSupported(cliVersion: SemanticVersion?) -> Bool {
        guard let cliVersion else { return false }
        return cliVersion >= minimumCLIVersion
    }
}

/// One setting a package declares (`packages list`'s `variables`): what
/// `--set <package>.<name>=…` accepts. `default` is the manifest's, never a
/// value somebody set; `type` is read off it and missing without one.
public struct PackageVariable: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case string, number, boolean, list, map
    }

    public let name: String
    public let summary: String
    public let `default`: SettingValue?
    public let type: Kind?

    public init(name: String, summary: String, default: SettingValue?, type: Kind?) {
        self.name = name
        self.summary = summary
        self.default = `default`
        self.type = type
    }

    enum CodingKeys: String, CodingKey {
        case name, summary, `default`, type
    }

    /// A type this app does not know reads as none: the field is then text.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        let value = try c.decodeIfPresent(SettingValue.self, forKey: .default)
        self.default = value == .null ? nil : value
        type = (try c.decodeIfPresent(String.self, forKey: .type)).flatMap(Kind.init(rawValue:))
    }

    public var defaultText: String { self.default?.text ?? "none" }

    /// Only a number is checked here; the CLI validates the rest.
    public func problem(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard type == .number, !value.isEmpty, Double(value) == nil else { return nil }
        return "\(name) takes a number."
    }
}

/// One login a workspace's packages use, and what it does when the
/// workspace says nothing: the configuration's answer, else the package's
/// own scope. `machine` shares the machine's login, `own` keeps one.
public struct WorkspaceLogin: Equatable, Sendable, Identifiable {
    public let name: String
    public let package: String
    public let inherited: String

    public var id: String { name }

    public init(name: String, package: String, inherited: String) {
        self.name = name
        self.package = package
        self.inherited = inherited
    }

    public static let machine = "machine"
    public static let own = "own"

    public static func logins(
        packages: [String], declared: [String: [PackageCredential]], configuration: [String: String]
    ) -> [WorkspaceLogin] {
        var seen = Set<String>()
        return packages.flatMap { package in
            (declared[package] ?? []).compactMap { credential in
                guard seen.insert(credential.name).inserted else { return nil }
                let fallback = credential.scope == machine ? machine : own
                return WorkspaceLogin(
                    name: credential.name, package: package, inherited: configuration[credential.name] ?? fallback)
            }
        }
    }
}

/// `workspaces edit --share <name>=<value>`: `machine`, `own`, or empty to
/// follow the configuration again.
public struct WorkspaceShare: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}
