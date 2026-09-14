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

    func logs(alias: String, lines: Int = 200) throws -> String {
        try remote.run(alias: alias, args: ["journalctl -u caddy -n \(lines) --no-pager"])
    }
}
