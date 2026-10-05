import Foundation

/// Settings → Workspaces: every workspace under the machine that holds it,
/// each with its on/off switch. The switch is the sidebar's hidden list,
/// keyed by ssh alias, so a workspace the sidebar does not know has none.
public enum WorkspaceSettingsList {
    public struct Machine: Equatable, Sendable {
        public let name: String
        public let location: String?

        public init(name: String, location: String?) {
            self.name = name
            self.location = location
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public let name: String
        /// Nil when only the sidebar knows it: the CLI's list did not hold it.
        public let summary: WorkspaceSummary?
        /// Nil when the sidebar does not know it: there is nothing to switch.
        public let alias: String?
        public let isActive: Bool

        public var id: String { name }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public let machine: String
        public let location: String?
        public let rows: [Row]

        public var id: String { machine }
    }

    /// The section of sidebar workspaces the CLI's list did not hold.
    public static let unknownMachine = ""

    /// Machines in the configuration's order, then any the list names that
    /// the configuration does not, then the sidebar's leftovers.
    public static func sections(
        summaries: [WorkspaceSummary], machines: [Machine], sidebar: [Workspace], hidden: [String]
    ) -> [Section] {
        let remote = sidebar.filter { !$0.isLocal }
        func alias(_ name: String) -> String? {
            remote.first { $0.name.lowercased() == name.lowercased() }?.alias
        }
        func row(_ name: String, summary: WorkspaceSummary?, alias: String?) -> Row {
            Row(
                name: name, summary: summary, alias: alias,
                isActive: alias.map { !WorkspaceVisibility.isHidden($0, hidden: hidden) } ?? true)
        }

        var order = machines.map(\.name)
        for summary in summaries where !order.contains(summary.machine) {
            order.append(summary.machine)
        }
        var sections: [Section] = order.compactMap { machine in
            let held = summaries.filter { $0.machine == machine }
            guard !held.isEmpty else { return nil }
            return Section(
                machine: machine, location: machines.first { $0.name == machine }?.location,
                rows: held.map { row($0.name, summary: $0, alias: alias($0.name)) })
        }
        let listed = Set(summaries.map { $0.name.lowercased() })
        let leftovers = remote.filter { !listed.contains($0.name.lowercased()) }
        if !leftovers.isEmpty {
            sections.append(Section(
                machine: unknownMachine, location: nil,
                rows: leftovers.map { row($0.name, summary: nil, alias: $0.alias) }))
        }
        return sections
    }
}
