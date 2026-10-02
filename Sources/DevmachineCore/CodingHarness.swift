import Foundation

public struct HarnessID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let claude = HarnessID(rawValue: "claude")
    public static let codex = HarnessID(rawValue: "codex")
    public static let pi = HarnessID(rawValue: "pi")
    public static let antigravity = HarnessID(rawValue: "antigravity")
    public static let opencode = HarnessID(rawValue: "opencode")
    public static let kimi = HarnessID(rawValue: "kimi")
    public static let cline = HarnessID(rawValue: "cline")
}

public enum SessionLaunchChoice: Codable, Equatable, Sendable {
    case terminal
    case harness(HarnessID)
    /// A command typed by hand, run as the session's first line the same way
    /// a harness starts.
    case custom(String)
}
