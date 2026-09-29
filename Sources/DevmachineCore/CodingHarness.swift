import Foundation

public struct HarnessID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let claude = HarnessID(rawValue: "claude")
    public static let codex = HarnessID(rawValue: "codex")
    public static let pi = HarnessID(rawValue: "pi")
}

public enum SessionLaunchChoice: Codable, Equatable, Sendable {
    case terminal
    case harness(HarnessID)
}
