import Foundation

/// `<package>/<command>`: a package's own command that feeds a widget.
/// `app/*` stays the app's, and a name never starts with `-`, so it can
/// never be read as a flag.
public enum PackageProviderName {
    static var pattern: Regex<(Substring, Substring, Substring)> {
        /([a-z][a-z0-9_-]*)\/([a-z][a-z0-9_-]*)/
    }

    public static func parts(_ name: String) -> (package: String, command: String)? {
        guard let match = name.wholeMatch(of: pattern), match.1 != "app" else { return nil }
        return (String(match.1), String(match.2))
    }

    /// The CLI's SplitProviderName: any `<a>/<b>` outside a reserved prefix
    /// is a package provider, so a malformed one is refused by its shape
    /// instead of reading as an unknown app provider.
    public static func claims(_ name: String, reserved: [String]) -> Bool {
        let pieces = name.split(separator: "/", omittingEmptySubsequences: false)
        return pieces.count == 2 && !pieces[0].isEmpty && !pieces[1].isEmpty && !reserved.contains(String(pieces[0]))
    }

    static func shapeProblem(_ name: String) -> String {
        "source.name \(name): is written <package>/<command>, each in lower case letters, digits, dashes and underscores, starting with a letter"
    }
}

/// What `package.yml` declares for one provider, as the catalog hands it over.
public struct PackageProviderSpec: Decodable, Hashable, Sendable {
    public let returns: [String: String]
    public let minEvery: String

    enum CodingKeys: String, CodingKey {
        case returns
        case minEvery = "min_every"
    }

    public init(returns: [String: String], minEvery: String) {
        self.returns = returns
        self.minEvery = minEvery
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        returns = try c.decodeIfPresent([String: String].self, forKey: .returns) ?? [:]
        minEvery = try c.decodeIfPresent(String.self, forKey: .minEvery) ?? ""
    }

    public var requiredFields: [String] {
        returns.filter { !$0.value.hasSuffix("?") }.keys.sorted()
    }
}

/// A widget source that runs a package provider on a machine or workspace.
public struct PackageProviderSource: Hashable, Sendable {
    public var name: String
    public var with: [String: String]
    public var target: WidgetTarget
    public var every: WidgetEvery
    public var timeout: TimeInterval
    public var returns: [String: String]

    public init(
        name: String, with: [String: String], target: WidgetTarget, every: WidgetEvery, timeout: TimeInterval,
        returns: [String: String] = [:]
    ) {
        self.name = name
        self.with = with
        self.target = target
        self.every = every
        self.timeout = timeout
        self.returns = returns
    }
}

/// The package providers the catalog knows. A package in `packages` lists
/// all its providers; only a complete index (a release was read) may call a
/// package missing, as `widgets validate` does; otherwise `devmachine run` does.
public struct PackageProviderIndex: Equatable, Sendable {
    public let providers: [String: PackageProviderSpec]
    public let packages: Set<String>
    public let isComplete: Bool

    public static let unknown = PackageProviderIndex(providers: [:], packages: [], isComplete: false)

    public init(providers: [String: PackageProviderSpec], packages: Set<String>, isComplete: Bool) {
        self.providers = providers
        self.packages = packages
        self.isComplete = isComplete
    }

    public func spec(for name: String) throws -> PackageProviderSpec? {
        if let spec = providers[name] { return spec }
        guard let parts = PackageProviderName.parts(name) else { return nil }
        guard packages.contains(parts.package) else {
            guard isComplete else { return nil }
            throw WidgetSpecProblem(["name"], "source.name \(name): no package \(parts.package) in the release or your own packages")
        }
        let prefix = parts.package + "/"
        let declared = providers.keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.sorted()
        let list = declared.isEmpty ? "none" : declared.joined(separator: ", ")
        throw WidgetSpecProblem(
            ["name"], "source.name \(name): \(parts.package) has no provider \(parts.command); its providers: \(list)")
    }
}
