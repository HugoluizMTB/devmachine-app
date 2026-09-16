import Foundation

/// A terminal this Mac hosts: a shell in a folder you picked. The name is what
/// the sidebar shows; the path is where the shell starts.
public struct LocalSession: Equatable, Identifiable, Sendable, Codable {
    /// The name the multiplexer knows. `zmx` has no rename, and the socket is
    /// named after the session, so this one can never change while the shell
    /// lives — only what the sidebar shows can.
    public let handle: String
    public var name: String
    public let path: String
    public var id: String { handle }

    public init(handle: String? = nil, name: String, path: String) {
        self.handle = handle ?? name
        self.name = name
        self.path = path
    }

    enum CodingKeys: String, CodingKey { case handle, name, path }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .name)
        self.name = name
        self.handle = try c.decodeIfPresent(String.self, forKey: .handle) ?? name
        self.path = try c.decode(String.self, forKey: .path)
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
