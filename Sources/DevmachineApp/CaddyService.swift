import Foundation
import DevmachineCore

/// Everything the Subdomains page's "Sites" tab needs, read in one pass: the
/// expose list, plus the stats package's ports and containers so a site with
/// no `workspace` (adopted, or the config disagrees with the machine) can
/// still say who owns it.
struct SubdomainsSnapshot: Sendable, Equatable {
    var rows: [SubdomainRow]
    var domain: String
}

struct CaddyService: Sendable {
    let cli: DevmachineCLI?
    private let adminMachine: AdminMachineCache

    init(cli: DevmachineCLI? = nil, adminMachine: AdminMachineCache = .shared) {
        self.cli = cli
        self.adminMachine = adminMachine
    }

    func snapshot() throws -> SubdomainsSnapshot {
        let cli = try resolvedCLI()
        let sites = try cli.listExposures()
        let workspaceUsers = try cli.listWorkspaces().map { WorkspaceUser(workspace: $0.name, user: $0.user) }
        let domain = (try? cli.configShow().domain) ?? ""

        var ports: [PortOwner] = []
        var containers: [ContainerStat] = []
        if let machine = try? adminMachine.name(cli: { cli }),
           let output = try? cli.run(machine: machine, package: "devmachine-app", args: ["stats"]),
           let parsed = StatsParser.parse(output) {
            ports = parsed.ports
            containers = parsed.containers
        }

        let rows = SubdomainRowBuilder.rows(sites: sites, ports: ports, workspaceUsers: workspaceUsers, containers: containers)
        return SubdomainsSnapshot(rows: rows, domain: domain)
    }

    /// Every installed DNS provider's name — the tab strip's own list.
    func dnsProviderNames() throws -> [String] {
        let cli = try resolvedCLI()
        let machine = try adminMachine.name(cli: { cli })
        return try cli.dnsProviders(machine: machine).map(\.name)
    }

    func dnsRecords(provider: String, zone: String) throws -> [DNSRecordRow] {
        let cli = try resolvedCLI()
        let machine = try adminMachine.name(cli: { cli })
        return try cli.dnsList(machine: machine, provider: provider, zone: zone)
    }

    func remove(host: String) throws {
        try resolvedCLI().unexpose(host: host)
    }

    /// `machine` is nil for the existing single-machine caller, which still
    /// gets the cached first non-self machine; a caller that knows there are
    /// several (the Stats machine switcher) names the one it wants logs from.
    /// `matching` filters the tail to lines mentioning that host — the
    /// per-row "Logs" action, in place of the old whole-machine log pane.
    func logs(machine: String? = nil, matching host: String? = nil, lines: Int = 200) throws -> String {
        let cli = try resolvedCLI()
        let resolvedMachine = try machine ?? adminMachine.name { cli }
        let text = try cli.run(
            machine: resolvedMachine, package: "devmachine-app",
            args: ["caddy-logs", "--lines", String(lines)])
        guard let host else { return text }
        let matching = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedCaseInsensitiveContains(host) }
        return matching.isEmpty ? "No log lines mention \(host) in the current tail." : matching.joined(separator: "\n")
    }

    private func resolvedCLI() throws -> DevmachineCLI {
        try cli ?? DevmachineCLI.resolve()
    }
}
