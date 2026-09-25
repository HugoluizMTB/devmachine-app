import Foundation

public struct CaddySite: Equatable, Sendable {
    public let address: String
    public let target: String
    public let kind: String
    public let workspace: String?

    public init(address: String, target: String, kind: String, workspace: String? = nil) {
        self.address = address
        self.target = target
        self.kind = kind
        self.workspace = workspace
    }
}

public enum CaddyfileParser {
    public static func parse(_ text: String) -> [CaddySite] {
        var sites: [CaddySite] = []
        var pendingAddresses: [String]?
        var pendingKind = "other"
        var pendingTarget = ""

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if pendingAddresses == nil {
                guard !line.isEmpty, !line.hasPrefix("#") else { continue }
                guard line.hasSuffix("{") else { continue }

                let addressPart = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
                let addressSeparators = CharacterSet(charactersIn: ",").union(.whitespaces)
                let addresses = addressPart
                    .components(separatedBy: addressSeparators)
                    .filter { !$0.isEmpty }
                guard !addresses.isEmpty else { continue }

                pendingAddresses = addresses
                pendingKind = "other"
                pendingTarget = ""
                continue
            }

            if line == "}" {
                for address in pendingAddresses ?? [] {
                    sites.append(CaddySite(address: address, target: pendingTarget, kind: pendingKind))
                }
                pendingAddresses = nil
                continue
            }

            guard pendingKind == "other" else { continue }

            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let directive = tokens.first else { continue }

            if directive == "reverse_proxy", tokens.count > 1 {
                pendingKind = "proxy"
                pendingTarget = tokens[1]
            } else if directive == "redir", tokens.count > 1 {
                pendingKind = "redir"
                pendingTarget = tokens[1]
            }
        }

        return sites
    }
}
