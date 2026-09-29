import Foundation
import DevmachineCore

/// What the app can read straight from the CLI instead of asking the person
/// to type it in Setup: the configuration folder, the admin machine's
/// address, the base domain, and every workspace's exact ssh alias.
struct CLIDetectedSettings: Equatable, Sendable {
    var opsRepoPath: String?
    var adminMachine: String?
    var publicIP: String?
    var baseDomain: String?
    var workspaceAliases: [String: String] = [:]

    static let empty = CLIDetectedSettings()
}

enum CLIAutoDetect {
    /// Best-effort: a call the CLI does not support yet, or one that fails
    /// (offline, no config), just leaves that part undetected — Setup still
    /// falls back to asking for it.
    static func detect(cli: () throws -> DevmachineCLI) -> CLIDetectedSettings {
        var result = CLIDetectedSettings.empty

        if let path = try? cli().configPath() {
            result.opsRepoPath = path.path
        }

        if let show = try? cli().configShow() {
            result.baseDomain = show.domain.isEmpty ? nil : show.domain
            if let machine = show.machines.first(where: { !$0.isSelf }) {
                result.adminMachine = machine.name
                result.publicIP = machine.hosts.first { !isTailscaleAddress($0) } ?? machine.hosts.first
            }

            if let aliases = try? cli().aliases() {
                let nonPublished = aliases.filter { !$0.name.hasSuffix("-pub") }
                for workspace in show.workspaces {
                    if let match = nonPublished.first(where: { $0.name == "\(workspace.name)-devmachine" })
                        ?? nonPublished.first(where: { $0.name.hasPrefix("\(workspace.name)-") }) {
                        result.workspaceAliases[workspace.name] = match.name
                    }
                }
            }
        }

        return result
    }

    /// `100.64.0.0/10` is the CGNAT range Tailscale hands out — this app's
    /// "public IP" is what a subdomain's A record should point at, never a
    /// tailnet-only address.
    static func isTailscaleAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127
    }
}
