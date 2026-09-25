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
