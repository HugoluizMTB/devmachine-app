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

}
