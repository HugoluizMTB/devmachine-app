import Foundation
import DevmachineCore

struct CaddyService: Sendable {
    let remote: RemoteService

    init(remote: RemoteService = RemoteService()) {
        self.remote = remote
    }

    func sites(alias: String) throws -> [CaddySite] {
        CaddyfileParser.parse(try remote.run(alias: alias, args: ["cat /etc/caddy/Caddyfile"]))
    }

    /// Who is behind each port the Caddyfile points at, so a site can be tied
    /// to the workspace that runs it.
    func portOwners(alias: String) throws -> [Int: String] {
        Ownership.portOwners(try remote.run(alias: alias, args: [RemoteCommands.portOwners]))
    }

    func logs(alias: String, lines: Int = 200) throws -> String {
        try remote.run(alias: alias, args: ["journalctl -u caddy -n \(lines) --no-pager"])
    }
}
