import Foundation

/// One row of `packages list`, as the Packages page needs it.
public struct PackageEntry: Equatable, Sendable, Identifiable {
    public let name: String
    public let scope: String
    public let source: String
    public let summary: String
    public let category: String?
    public let platforms: [String]
    public let needs: [String]
    public let credentialNames: [String]
    public let installedOn: [String]

    public init(name: String, scope: String, source: String, summary: String, category: String?,
                platforms: [String], needs: [String], credentialNames: [String], installedOn: [String]) {
        self.name = name
        self.scope = scope
        self.source = source
        self.summary = summary
        self.category = category
        self.platforms = platforms
        self.needs = needs
        self.credentialNames = credentialNames
        self.installedOn = installedOn
    }

    public var id: String { name }
    public var isLocal: Bool { source == "local" }
    public var categoryTitle: String {
        guard let category, !category.isEmpty else { return PackageFilter.otherCategory }
        return category
    }
}
