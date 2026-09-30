import Foundation
import DevmachineCore

/// What the Subdomains page reads once per refresh, for every machine: the
/// domain new subdomains go under, which machine each workspace lives on,
/// and which packages each machine has. `installedPackages` is nil when the
/// CLI could not say, and then nothing is ruled out ahead of asking.
struct SitesContext: Sendable, Equatable {
    var domain: String = ""
    var workspaces: [CLIWorkspace] = []
    var installedPackages: [CLIPackage]?

    func workspaces(on machine: String) -> [String] {
        workspaces.filter { $0.machine == machine }.map(\.name)
    }

    func hasCaddy(onMachine machine: String) -> Bool? {
        guard let installedPackages else { return nil }
        let names = Set(installedPackages.filter { $0.isInstalled(onMachine: machine) }.map(\.name))
        return CaddyDetection.hasCaddy(installedPackageNames: names)
    }
}

/// One machine's answer to "what is published here".
enum MachineSitesResult: Sendable, Equatable {
    case sites([SubdomainRow])
    case notSetUp(String)
}

/// Every CLI call the Subdomains page makes. Each one that acts on a server
/// names its machine: with several configured, the CLI refuses to guess.
struct CaddyService: Sendable {
    let cli: DevmachineCLI?

    init(cli: DevmachineCLI? = nil) {
        self.cli = cli
    }

    func machines() throws -> [CLIMachine] {
        try resolvedCLI().listMachines()
    }

    func context() -> SitesContext {
        guard let cli = try? resolvedCLI() else { return SitesContext() }
        return SitesContext(
            domain: (try? cli.configShow().domain) ?? "",
            workspaces: (try? cli.listWorkspaces()) ?? [],
            installedPackages: try? cli.packages())
    }

    /// This Mac, and a server without caddy, have nothing to publish from;
    /// both answer without a connection. The stats read only adds owners to
    /// rows that carry no workspace, so its failure never fails the list.
    func sites(on machine: CLIMachine, context: SitesContext) throws -> MachineSitesResult {
        if machine.isSelf {
            return .notSetUp(Self.selfMessage(machine.name))
        }
        if context.hasCaddy(onMachine: machine.name) == false {
            return .notSetUp(Self.noCaddyMessage(machine.name))
        }
        let cli = try resolvedCLI()
        let listing = try cli.listExposures(machine: machine.name)
        if listing.sites.isEmpty && listing.caddyIsMissing {
            return .notSetUp(Self.noCaddyMessage(machine.name))
        }

        var ports: [PortOwner] = []
        var containers: [ContainerStat] = []
        if let output = try? cli.run(machine: machine.name, package: "devmachine-app", args: ["stats"]),
           let parsed = StatsParser.parse(output) {
            ports = parsed.ports
            containers = parsed.containers
        }
        let workspaceUsers = context.workspaces
            .filter { $0.machine == machine.name }
            .map { WorkspaceUser(workspace: $0.name, user: $0.user) }
        return .sites(SubdomainRowBuilder.rows(
            sites: listing.sites, ports: ports, workspaceUsers: workspaceUsers, containers: containers))
    }

    static func selfMessage(_ machine: String) -> String {
        "\(machine) is this Mac. Sites are published from a server with Caddy, so there is nothing to list here."
    }

    static func noCaddyMessage(_ machine: String) -> String {
        "\(machine) is not set up for sites yet. Add Caddy with `devmachine packages add caddy --machine \(machine)`, "
            + "then run `devmachine sync --machine \(machine)`."
    }

    /// DNS providers are packages, installed per machine: the tab strip
    /// lists the ones on `machine`.
    func dnsProviderNames(machine: String) throws -> [String] {
        try resolvedCLI().dnsProviders(machine: machine).map(\.name)
    }

    func dnsRecords(machine: String, provider: String, zone: String) throws -> [DNSRecordRow] {
        try resolvedCLI().dnsList(machine: machine, provider: provider, zone: zone)
    }

    func remove(host: String, machine: String) throws {
        try resolvedCLI().unexpose(host: host, machine: machine)
    }

    /// `matching` filters the tail to lines mentioning that host — the
    /// per-row "Logs" action.
    func logs(machine: String, matching host: String? = nil, lines: Int = 200) throws -> String {
        let text = try resolvedCLI().run(
            machine: machine, package: "devmachine-app",
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
