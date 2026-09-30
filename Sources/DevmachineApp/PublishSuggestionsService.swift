import Foundation
import DevmachineCore

/// What the quick-publish sheet needs before it opens: the ports this
/// workspace's own processes and containers are listening on, and the domain
/// a suggested hostname is built under.
struct QuickPublishSuggestions: Sendable, Equatable {
    var ports: [PortSuggestion] = []
    var domain: String = ""
}

/// Resolves a workspace's own listening ports — read fresh each time a
/// workspace row's "Publish a port…" is used, rather than kept in `AppModel`:
/// this is a rare, one-shot lookup, not something the rest of the app reads.
struct PublishSuggestionsService: Sendable {
    let cli: DevmachineCLI?

    init(cli: DevmachineCLI? = nil) {
        self.cli = cli
    }

    /// Stats are read on the machine the workspace lives on — with several
    /// machines, any other one has none of its ports.
    func suggestions(forWorkspace workspace: String) -> QuickPublishSuggestions {
        guard let cli = try? resolvedCLI() else { return QuickPublishSuggestions() }
        let domain = (try? cli.configShow().domain) ?? ""
        guard let entry = try? cli.listWorkspaces().first(where: { $0.name == workspace }),
              let output = try? cli.run(machine: entry.machine, package: "devmachine-app", args: ["stats"]),
              let snapshot = StatsParser.parse(output) else {
            return QuickPublishSuggestions(ports: [], domain: domain)
        }
        let ports = PublishSuggestions.ports(forUser: entry.user, ports: snapshot.ports, containers: snapshot.containers)
        return QuickPublishSuggestions(ports: ports, domain: domain)
    }

    private func resolvedCLI() throws -> DevmachineCLI {
        try cli ?? DevmachineCLI.resolve()
    }
}
