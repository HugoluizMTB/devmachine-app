import Foundation
import DevmachineCore

struct CaddyService: Sendable {
    let cli: DevmachineCLI?
    private let adminMachine: AdminMachineCache

    init(cli: DevmachineCLI? = nil, adminMachine: AdminMachineCache = .shared) {
        self.cli = cli
        self.adminMachine = adminMachine
    }

    func sites() throws -> [CaddySite] {
        let published = try resolvedCLI().listExposures()
        return published.map {
            CaddySite(
                address: $0.host,
                target: "127.0.0.1:\($0.port)",
                kind: "proxy",
                workspace: $0.workspace
            )
        }
    }

    /// `machine` is nil for the existing single-machine caller, which still
    /// gets the cached first non-self machine; a caller that knows there are
    /// several (the Stats machine switcher) names the one it wants logs from.
    func logs(machine: String? = nil, lines: Int = 200) throws -> String {
        let cli = try resolvedCLI()
        let resolvedMachine = try machine ?? adminMachine.name { cli }
        return try cli.run(
            machine: resolvedMachine, package: "devmachine-app",
            args: ["caddy-logs", "--lines", String(lines)])
    }

    private func resolvedCLI() throws -> DevmachineCLI {
        try cli ?? DevmachineCLI.resolve()
    }
}
