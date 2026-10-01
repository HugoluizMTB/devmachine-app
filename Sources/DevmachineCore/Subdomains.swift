import Foundation

/// One row `expose list --format json` reports: a site the configuration and
/// the machine agree, or disagree, about.
public struct ExposedSite: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Equatable, Sendable {
        case published, pending, unmanaged, differs, unknown

        /// A short word for the status pill.
        public var title: String {
            switch self {
            case .published: return "Published"
            case .pending: return "Pending"
            case .unmanaged: return "Unmanaged"
            case .differs: return "Differs"
            case .unknown: return "Unknown"
            }
        }
    }

    public let host: String
    public let port: Int
    public let workspace: String?
    public let status: Status
    public let note: String?

    public var id: String { host }

    enum CodingKeys: String, CodingKey {
        case host, port, workspace, status, note
    }

    public init(host: String, port: Int, workspace: String?, status: Status, note: String? = nil) {
        self.host = host
        self.port = port
        self.workspace = workspace
        self.status = status
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        workspace = try c.decodeIfPresent(String.self, forKey: .workspace)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        let raw = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        status = Status(rawValue: raw) ?? .unknown
    }
}

/// One record `dns list <zone> --format json` reports for an installed
/// provider's zone.
public struct DNSRecordRow: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let type: String
    public let value: String
    public let ttl: Int

    public var id: String { "\(name)/\(type)/\(value)" }

    enum CodingKeys: String, CodingKey {
        case name, type, value, ttl
    }

    public init(name: String, type: String, value: String, ttl: Int) {
        self.name = name
        self.type = type
        self.value = value
        self.ttl = ttl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(String.self, forKey: .type)
        value = try c.decode(String.self, forKey: .value)
        ttl = try c.decodeIfPresent(Int.self, forKey: .ttl) ?? 0
    }
}

/// The tab strip above the subdomains table: "Sites" (the app's own
/// `expose list`), then one tab per installed DNS provider — never a
/// provider that is not there, so an unconfigured Hostinger never shows an
/// empty, permanently failing tab.
public enum SubdomainsTab: Equatable, Sendable, Hashable {
    case sites
    case provider(String)

    public var title: String {
        switch self {
        case .sites: return "Sites"
        case .provider(let name): return name
        }
    }
}

public enum SubdomainsTabs {
    public static func build(providers: [String]) -> [SubdomainsTab] {
        [.sites] + providers.map { .provider($0) }
    }
}

/// Whether a machine has Caddy: directly, as `caddy`, or through the
/// `essentials` package, which installs it alongside base tools, git and the
/// firewall (`devmachine setup`'s starting bundle).
public enum CaddyDetection {
    static let providingPackages: Set<String> = ["caddy", "essentials"]

    public static func hasCaddy(installedPackageNames: Set<String>) -> Bool {
        !installedPackageNames.isDisjoint(with: providingPackages)
    }

    /// True when at least one of the given machines' installed package sets
    /// has Caddy — the question the sidebar's icon answers.
    public static func anyMachineHasCaddy(installedPackageNamesByMachine: [Set<String>]) -> Bool {
        installedPackageNamesByMachine.contains { hasCaddy(installedPackageNames: $0) }
    }
}

/// A workspace's Linux user, the join key between `workspaces list` and a
/// port's owner in the stats package's `ports`.
public struct WorkspaceUser: Equatable, Sendable {
    public let workspace: String
    public let user: String

    public init(workspace: String, user: String) {
        self.workspace = workspace
        self.user = user
    }
}

/// Maps a listening port back to the workspace whose context user owns it —
/// the package stats report a Linux user, not a workspace name.
public enum PortWorkspaceMapping {
    public static func workspace(forPort port: Int, ports: [PortOwner], workspaceUsers: [WorkspaceUser]) -> String? {
        guard let owner = ports.first(where: { $0.port == port })?.owner else { return nil }
        return workspaceUsers.first(where: { $0.user == owner })?.workspace
    }
}

/// One port suggested for a quick publish, with the container behind it when
/// exactly one owned container makes the match unambiguous. The stats
/// contract has no port-to-container link, so a port with more than one
/// candidate container is offered with no name rather than a guess.
public struct PortSuggestion: Equatable, Sendable, Identifiable {
    public let port: Int
    public let containerName: String?
    public var id: Int { port }

    public init(port: Int, containerName: String? = nil) {
        self.port = port
        self.containerName = containerName
    }
}

public enum PublishSuggestions {
    /// Listening ports owned by `user`, each paired with its container's name
    /// when that user owns exactly one container.
    public static func ports(forUser user: String, ports: [PortOwner], containers: [ContainerStat]) -> [PortSuggestion] {
        let ownedContainers = containers.filter { $0.owner == user }
        let containerName = ownedContainers.count == 1 ? ownedContainers[0].name : nil
        var seen = Set<Int>()
        var result: [PortSuggestion] = []
        for p in ports where p.owner == user {
            guard seen.insert(p.port).inserted else { continue }
            result.append(PortSuggestion(port: p.port, containerName: containerName))
        }
        return result.sorted { $0.port < $1.port }
    }

    public static func hostname(label: String, domain: String) -> String {
        "\(label).\(domain)"
    }
}

/// One row the Subdomains table draws: an `ExposedSite`, plus whatever the
/// port lets us add when the site itself carries no workspace (an unmanaged
/// site the CLI found only on the machine).
public struct SubdomainRow: Equatable, Sendable, Identifiable {
    public let site: ExposedSite
    public let resolvedWorkspace: String?
    public let containerName: String?
    public var id: String { site.host }

    public init(site: ExposedSite, resolvedWorkspace: String?, containerName: String?) {
        self.site = site
        self.resolvedWorkspace = resolvedWorkspace
        self.containerName = containerName
    }

    /// What the Workspace column shows: the resolved workspace when there is
    /// one, else the owning container's name as a hint, else nothing.
    public var workspaceDisplay: String? { resolvedWorkspace ?? containerName }

    /// True when `workspaceDisplay` came from the container hint, not a real
    /// workspace match — the table renders that case muted.
    public var workspaceIsContainerHint: Bool { resolvedWorkspace == nil && containerName != nil }
}

public enum SubdomainRowBuilder {
    public static func rows(
        sites: [ExposedSite], ports: [PortOwner], workspaceUsers: [WorkspaceUser], containers: [ContainerStat]
    ) -> [SubdomainRow] {
        sites.map { site in
            let owner = ports.first(where: { $0.port == site.port })?.owner
            let mappedWorkspace = site.workspace
                ?? PortWorkspaceMapping.workspace(forPort: site.port, ports: ports, workspaceUsers: workspaceUsers)
            var containerName: String?
            if let owner {
                let owned = containers.filter { $0.owner == owner }
                containerName = owned.count == 1 ? owned[0].name : nil
            }
            return SubdomainRow(site: site, resolvedWorkspace: mappedWorkspace, containerName: containerName)
        }
    }
}

/// Filters a list of rows by a free-text query against each row's searchable
/// fields — the "Search subdomains" field, shared with the DNS tables.
public enum RowSearch {
    public static func filter<T>(_ rows: [T], query: String, fields: (T) -> [String]) -> [T] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { row in fields(row).contains { $0.lowercased().contains(q) } }
    }
}
