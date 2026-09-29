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

    func logs(lines: Int = 200) throws -> String {
        let cli = try resolvedCLI()
        let machine = try adminMachine.name { cli }
        return try cli.run(machine: machine, command: "journalctl -u caddy -n \(lines) --no-pager")
    }

    private func resolvedCLI() throws -> DevmachineCLI {
        try cli ?? DevmachineCLI.resolve()
    }
}
