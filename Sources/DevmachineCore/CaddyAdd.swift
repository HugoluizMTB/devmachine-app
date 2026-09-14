import Foundation

public struct SubdomainRequest: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let managedDNS: Bool

    public init(host: String, port: Int, managedDNS: Bool) {
        self.host = host
        self.port = port
        self.managedDNS = managedDNS
    }

    public static func subdomain(label: String, port: Int, baseDomain: String) -> SubdomainRequest {
        SubdomainRequest(host: "\(label).\(baseDomain)", port: port, managedDNS: true)
    }
}

public enum CaddyAddError: Error, Equatable {
    case invalidLabel
    case invalidPort
    case alreadyExists
    case notCleanOrSynced(String)
}

public enum CaddyAdd {
    public static func validate(_ req: SubdomainRequest) throws {
        let hostRegex = "^[a-z0-9.-]+$"
        guard !req.host.isEmpty,
              req.host.contains("."),
              req.host.range(of: hostRegex, options: .regularExpression) != nil
        else {
            throw CaddyAddError.invalidLabel
        }
        guard 1...65535 ~= req.port else {
            throw CaddyAddError.invalidPort
        }
    }

    public static func appendBlock(to caddyfile: String, req: SubdomainRequest) throws -> String {
        try validate(req)

        let address = req.host
        guard !caddyfile.contains(address) else {
            throw CaddyAddError.alreadyExists
        }

        let trimmed = caddyfile.replacingOccurrences(of: "\\n+$", with: "", options: .regularExpression)
        let block = "\(address) {\n    reverse_proxy 127.0.0.1:\(req.port)\n}"

        if trimmed.isEmpty {
            return block + "\n"
        }
        return trimmed + "\n\n" + block + "\n"
    }

    public static func label(_ req: SubdomainRequest, baseDomain: String) -> String {
        String(req.host.dropLast(".\(baseDomain)".count))
    }

    public static func dnsBody(
        _ req: SubdomainRequest, baseDomain: String, ip: String, ttl: Int = 14400
    ) -> String {
        let name = label(req, baseDomain: baseDomain)
        return "{\"overwrite\":false,\"zone\":[{\"name\":\"\(name)\",\"type\":\"A\",\"ttl\":\(ttl),\"records\":[{\"content\":\"\(ip)\"}]}]}"
    }

    public static func hostingerCurl(_ req: SubdomainRequest, baseDomain: String, ip: String) -> String {
        let body = dnsBody(req, baseDomain: baseDomain, ip: ip)
        return "curl -s -X PUT \"https://developers.hostinger.com/api/dns/v1/zones/\(baseDomain)\" -H \"Authorization: Bearer $HOSTINGER_API_TOKEN\" -H \"Content-Type: application/json\" -d '\(body)'"
    }

    public static func ansibleApply() -> String {
        "cd ansible && ansible-playbook -i inventory.ini site.yml --tags caddy"
    }

    public static func isCleanAndSynced(porcelain: String, localHead: String, remoteHead: String) -> Bool {
        porcelain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && localHead.trimmingCharacters(in: .whitespacesAndNewlines) == remoteHead.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func hostingRow(_ req: SubdomainRequest) -> String {
        let status = req.managedDNS ? "⏳ pendente" : "⏳ pendente (DNS externo)"
        return "| `\(req.host)` | `127.0.0.1:\(req.port)` | \(status) |"
    }
}
