import Foundation

/// `<package>/<command>`: a package's own command that feeds a widget.
/// `app/*` stays the app's, and a name never starts with `-`, so it can
/// never be read as a flag.
public enum PackageProviderName {
    static var pattern: Regex<(Substring, Substring, Substring)> {
        /([a-z0-9][a-z0-9._-]*)\/([a-z0-9][a-z0-9._-]*)/
    }

    public static func parts(_ name: String) -> (package: String, command: String)? {
        guard let match = name.wholeMatch(of: pattern), match.1 != "app" else { return nil }
        return (String(match.1), String(match.2))
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

/// The package providers the catalog knows. Only a complete index (the CLI
/// listed every one) may call a name missing; otherwise `devmachine run` does.
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
        guard isComplete, let parts = PackageProviderName.parts(name) else { return nil }
        guard packages.contains(parts.package) else { throw WidgetSpecProblem(["name"], "no package \(parts.package)") }
        throw WidgetSpecProblem(["name"], "\(parts.package) has no provider \(parts.command)")
    }
}
