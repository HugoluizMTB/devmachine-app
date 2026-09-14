import Foundation

/// A terminal this Mac hosts: a shell in a folder you picked. The name is what
/// the sidebar shows; the path is where the shell starts.
public struct LocalSession: Equatable, Identifiable, Sendable, Codable {
    public let name: String
    public let path: String
    public var id: String { name }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum LocalSessionNaming {
    /// The folder's own name, and a number when that name is taken: two
    /// sessions with one name would collide as sidebar rows and as terminal
    /// registry keys.
    public static func name(for path: String, existing: [String]) -> String {
        // The root folder's last component is "/", which is not a name.
        let base = URL(fileURLWithPath: path).lastPathComponent
        let candidate = (base.isEmpty || base == "/") ? "shell" : base
        guard existing.contains(candidate) else { return candidate }
        var suffix = 2
        while existing.contains("\(candidate) \(suffix)") { suffix += 1 }
        return "\(candidate) \(suffix)"
    }
}
