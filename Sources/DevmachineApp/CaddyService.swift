import Foundation
import DevmachineCore

struct CaddyService: Sendable {
    let cli: DevmachineCLI?
    let remote: RemoteService

    init(cli: DevmachineCLI? = nil, remote: RemoteService = RemoteService()) {
        self.cli = cli
        self.remote = remote
    }

    func sites(alias: String) throws -> [CaddySite] {
        let published = try (cli ?? DevmachineCLI.resolve()).listExposures()
        return published.map {
            CaddySite(
                address: $0.host,
                target: "127.0.0.1:\($0.port)",
                kind: "proxy",
                workspace: $0.workspace
            )
        }
    }

    func logs(alias: String, lines: Int = 200) throws -> String {
        try remote.run(alias: alias, args: ["journalctl -u caddy -n \(lines) --no-pager"])
    }
}
