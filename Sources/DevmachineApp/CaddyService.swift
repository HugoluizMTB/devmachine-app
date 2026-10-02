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
    /// both answer without a connection.
    func preflight(_ machine: CLIMachine, context: SitesContext) -> MachineSitesResult? {
        if machine.isSelf {
            return .notSetUp(Self.selfMessage(machine.name))
        }
        if context.hasCaddy(onMachine: machine.name) == false {
            return .notSetUp(Self.noCaddyMessage(machine.name))
        }
        return nil
    }

    /// `expose list` for one machine: the one ssh the Subdomains page and
    /// the Preview tab share through the cache.
    func listing(on machine: String) throws -> ExposureListing {
        try resolvedCLI().listExposures(machine: machine)
    }

    /// The rows for a listing. Owners come from the stats the app already
    /// polls (`StatsStore`), never from a second stats read here: they only
    /// add names to rows that carry no workspace.
    static func result(
        for machine: CLIMachine, listing: ExposureListing, context: SitesContext, snapshot: StatsSnapshot?
    ) -> MachineSitesResult {
        if listing.sites.isEmpty && listing.caddyIsMissing {
            return .notSetUp(noCaddyMessage(machine.name))
        }
        let workspaceUsers = context.workspaces
            .filter { $0.machine == machine.name }
            .map { WorkspaceUser(workspace: $0.name, user: $0.user) }
        return .sites(SubdomainRowBuilder.rows(
            sites: listing.sites, ports: snapshot?.ports ?? [], workspaceUsers: workspaceUsers,
            containers: snapshot?.containers ?? []))
    }

    func sites(on machine: CLIMachine, context: SitesContext, snapshot: StatsSnapshot? = nil) throws -> MachineSitesResult {
        if let answer = preflight(machine, context: context) { return answer }
        return Self.result(for: machine, listing: try listing(on: machine.name), context: context, snapshot: snapshot)
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
    func dnsProviders(machine: String) throws -> [DNSProviderAnswer] {
        try resolvedCLI().dnsProviders(machine: machine)
    }

    func addPackage(_ package: String, machine: String) throws {
        try resolvedCLI().addPackage(package, machine: machine)
    }

    func setZones(setting: String, machine: String, zones: [String]) throws {
        try resolvedCLI().setZones(setting: setting, machine: machine, zones: zones)
    }

    func setSecret(_ name: String, value: String) throws {
        try resolvedCLI().setSecret(name, value: value)
    }

    func dnsRecords(machine: String, provider: String, zone: String) throws -> [DNSRecordRow] {
        try resolvedCLI().dnsList(machine: machine, provider: provider, zone: zone)
    }

    func publish(workspace: String, port: Int, host: String, via: String? = nil) throws -> CLIOutput {
        try resolvedCLI().exposeAdd(workspace: workspace, port: port, host: host, via: via)
    }

    func remove(host: String, machine: String) throws -> CLIOutput {
        try resolvedCLI().exposeRemove(host: host, machine: machine)
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
