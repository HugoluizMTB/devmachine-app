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
    /// False when the package says a copy of its login does not work on
    /// another account; nil when the CLI does not say (older than 0.7.29).
    public let shareable: Bool?

    public var id: String { name }

    public init(name: String, package: String, inherited: String, shareable: Bool? = nil) {
        self.name = name
        self.package = package
        self.inherited = inherited
        self.shareable = shareable
    }

    /// The answers Edit offers: "" follows the configuration. Shared is left
    /// out only when the CLI says the login cannot be copied.
    public var choices: [String] {
        shareable == false ? ["", Self.own] : ["", Self.machine, Self.own]
    }

    public var unshareableReason: String? {
        shareable == false
            ? "\(package) says a copy of this login does not work on another account, so each workspace logs in itself."
            : nil
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
                // sync turns a login that cannot be shared into the
                // workspace's own, whatever the configuration asks.
                guard credential.shareable != false else {
                    return WorkspaceLogin(name: credential.name, package: package, inherited: own, shareable: false)
                }
                let fallback = credential.scope == machine ? machine : own
                return WorkspaceLogin(
                    name: credential.name, package: package, inherited: configuration[credential.name] ?? fallback,
                    shareable: credential.shareable)
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
