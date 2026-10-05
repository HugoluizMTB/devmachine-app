import Foundation

/// What the network map is drawn from: the configured machines and the
/// sites their Caddy publishes. Nothing here is guessed: a link is drawn only
/// when the configuration says it exists.
public struct NetworkMapInput: Equatable, Sendable {
    public struct Machine: Equatable, Sendable {
        public let name: String
        public let location: String
        public let hosts: [String]
        public let isSelf: Bool
        public let isLocalVM: Bool
        public let hasCaddy: Bool
        public let workspaces: [String]

        public init(
            name: String, location: String, hosts: [String], isSelf: Bool, isLocalVM: Bool, hasCaddy: Bool,
            workspaces: [String]
        ) {
            self.name = name
            self.location = location
            self.hosts = hosts
            self.isSelf = isSelf
            self.isLocalVM = isLocalVM
            self.hasCaddy = hasCaddy
            self.workspaces = workspaces
        }

        /// The internet reaches a server's Caddy; a Lima machine on this
        /// Mac's loopback is out of its reach whatever it installs.
        var isDoor: Bool { hasCaddy && !isSelf && !isLocalVM }

        var isOnTailnet: Bool { hosts.contains(where: NetworkAddress.isTailnet) }
    }

    public struct Site: Equatable, Sendable {
        public let host: String
        public let servingMachine: String
        public let workspace: String?

        public init(host: String, servingMachine: String, workspace: String?) {
            self.host = host
            self.servingMachine = servingMachine
            self.workspace = workspace
        }
    }

    public let machines: [Machine]
    public let sites: [Site]

    public init(machines: [Machine], sites: [Site]) {
        self.machines = machines
        self.sites = sites
    }
}

/// The machines laid out by location, with the links between them. Columns
/// run left to right: this Mac's zone first, then the zones with a door to
/// the internet, then the rest by name.
public struct NetworkMap: Equatable, Sendable {
    public static let thisMacID = "this-mac"
    public static let internetID = "internet"
    public static let maximumSites = 6
    /// The extra columns between two zones.
    static let zoneGap = 0.45

    public enum NodeKind: Equatable, Sendable {
        case internet, thisMac, server, localVM
    }

    public struct Node: Equatable, Sendable, Identifiable {
        public let id: String
        public let kind: NodeKind
        public let zone: String?
        /// Its Caddy is where the internet comes in.
        public let isDoor: Bool
        public let workspaces: [String]
        public let column: Double
        /// A configured machine, which the list below can select.
        public let selectable: Bool
    }

    public struct Zone: Equatable, Sendable {
        public let name: String
        public let machines: [String]
        public let firstColumn: Double
        public let lastColumn: Double
    }

    public enum LinkKind: Equatable, Sendable {
        case https, site, ssh, tailnet
    }

    public struct Link: Equatable, Sendable {
        public let kind: LinkKind
        public let from: String
        public let to: String
        /// For a site: its row among the sites.
        public let row: Int?
    }

    public struct Site: Equatable, Sendable {
        public let host: String
        public let door: String
        public let target: String
        public let workspace: String?
        public let row: Int
    }

    public let zones: [Zone]
    public let nodes: [Node]
    public let links: [Link]
    public let sites: [Site]
    /// Sites left off the map to keep it readable.
    public let hiddenSites: Int

    public var machineNodes: [Node] { nodes.filter { $0.kind != .internet } }

    public func node(_ id: String) -> Node? { nodes.first { $0.id == id } }

    public static func build(_ input: NetworkMapInput) -> NetworkMap {
        guard !input.machines.isEmpty else {
            return NetworkMap(zones: [], nodes: [], links: [], sites: [], hiddenSites: 0)
        }
        var machines = input.machines
        if !machines.contains(where: \.isSelf) {
            machines.append(NetworkMapInput.Machine(
                name: thisMacID, location: MachineLocation.local, hosts: [], isSelf: true, isLocalVM: false,
                hasCaddy: false, workspaces: []))
        }
        let byZone = Dictionary(grouping: machines, by: \.location)
        let ordered = byZone.keys.sorted { lhs, rhs in
            zoneRank(lhs, byZone[lhs] ?? []) < zoneRank(rhs, byZone[rhs] ?? [])
        }

        var zones: [Zone] = []
        var nodes: [Node] = []
        var column = 0.0
        for (index, name) in ordered.enumerated() {
            if index > 0 { column += zoneGap }
            let members = (byZone[name] ?? []).sorted(by: machineOrder)
            let first = column
            for machine in members {
                nodes.append(Node(
                    id: machine.name, kind: kind(of: machine), zone: name, isDoor: machine.isDoor,
                    workspaces: machine.workspaces, column: column, selectable: machine.name != thisMacID))
                column += 1
            }
            zones.append(Zone(name: name, machines: members.map(\.name), firstColumn: first, lastColumn: column - 1))
        }

        let doors = nodes.filter(\.isDoor)
        var links: [Link] = []
        if !doors.isEmpty {
            let middle = doors.map(\.column).reduce(0, +) / Double(doors.count)
            nodes.insert(Node(
                id: internetID, kind: .internet, zone: nil, isDoor: false, workspaces: [], column: middle,
                selectable: false), at: 0)
            links += doors.map { Link(kind: .https, from: internetID, to: $0.id, row: nil) }
        }

        let columnOf = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.column) })
        let ownerOf = Dictionary(
            machines.flatMap { machine in machine.workspaces.map { ($0, machine.name) } },
            uniquingKeysWith: { first, _ in first })
        let doorNames = Set(doors.map(\.id))
        let served = input.sites
            .filter { doorNames.contains($0.servingMachine) }
            .sorted { lhs, rhs in
                let left = columnOf[lhs.servingMachine] ?? 0, right = columnOf[rhs.servingMachine] ?? 0
                return left == right ? lhs.host < rhs.host : left < right
            }
        let shown = served.prefix(maximumSites)
        let sites = shown.enumerated().map { row, site in
            Site(
                host: site.host, door: site.servingMachine,
                target: site.workspace.flatMap { ownerOf[$0] } ?? site.servingMachine,
                workspace: site.workspace, row: row)
        }
        links += sites.map { Link(kind: .site, from: $0.door, to: $0.target, row: $0.row) }

        if let mac = nodes.first(where: { $0.kind == .thisMac }) {
            links += nodes.filter { $0.kind == .server || $0.kind == .localVM }
                .map { Link(kind: .ssh, from: mac.id, to: $0.id, row: nil) }
        }

        let onTailnet = Set(machines.filter(\.isOnTailnet).map(\.name))
        let tailnet = nodes.filter { onTailnet.contains($0.id) }
        links += zip(tailnet, tailnet.dropFirst()).map { Link(kind: .tailnet, from: $0.id, to: $1.id, row: nil) }

        return NetworkMap(
            zones: zones, nodes: nodes, links: links, sites: sites, hiddenSites: served.count - shown.count)
    }

    private static func kind(of machine: NetworkMapInput.Machine) -> NodeKind {
        if machine.isSelf { return .thisMac }
        return machine.isLocalVM ? .localVM : .server
    }

    private static func zoneRank(_ name: String, _ machines: [NetworkMapInput.Machine]) -> (Int, String) {
        if machines.contains(where: \.isSelf) { return (0, name) }
        if machines.contains(where: \.isDoor) { return (1, name) }
        return (2, name)
    }

    private static func machineOrder(_ lhs: NetworkMapInput.Machine, _ rhs: NetworkMapInput.Machine) -> Bool {
        func rank(_ machine: NetworkMapInput.Machine) -> Int {
            if machine.isSelf { return 0 }
            return machine.isDoor ? 1 : 2
        }
        return rank(lhs) == rank(rhs) ? lhs.name < rhs.name : rank(lhs) < rank(rhs)
    }
}
