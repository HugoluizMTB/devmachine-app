public struct Workspace: Equatable, Identifiable, Sendable {
    /// Where this workspace's sessions live. A remote one is reached over ssh
    /// by its alias; a local one runs on this Mac and must never be handed to
    /// ssh. Every caller branches on this, never on the alias: an alias that
    /// looks local is not proof, and a silent fall back to the local machine
    /// would run a command in the wrong place.
    public enum Kind: Equatable, Sendable {
        case remote
        case local
    }

    public let name: String
    public let alias: String
    public let kind: Kind
    public var id: String { alias }
    public var isLocal: Bool { kind == .local }

    public init(name: String, alias: String, kind: Kind = .remote) {
        self.name = name
        self.alias = alias
        self.kind = kind
    }

    /// This Mac, always the last workspace in the sidebar.
    public static let local = Workspace(name: "Local", alias: "local", kind: .local)

    /// The session Local always has: the operator shell for the ops repository.
    public static let operatorSession = "Operator"
}

public enum WorkspaceVisibility {
    /// The workspaces the sidebar shows, and the only ones worth an ssh: a
    /// hidden workspace is neither drawn nor polled.
    public static func visible(_ all: [Workspace], hidden: [String]) -> [Workspace] {
        let hiddenSet = Set(hidden.map { $0.lowercased() })
        return all.filter { !hiddenSet.contains($0.alias.lowercased()) }
    }

    public static func isHidden(_ alias: String, hidden: [String]) -> Bool {
        hidden.contains { $0.lowercased() == alias.lowercased() }
    }

    /// Adding and removing keeps the list free of repeats and of aliases that
    /// differ only in case, which would hide a workspace twice over.
    public static func toggling(_ alias: String, in hidden: [String]) -> [String] {
        if isHidden(alias, hidden: hidden) {
            return hidden.filter { $0.lowercased() != alias.lowercased() }
        }
        return hidden + [alias]
    }

    /// A switch set to the value it already has changes nothing.
    public static func setting(_ alias: String, active: Bool, in hidden: [String]) -> [String] {
        isHidden(alias, hidden: hidden) == active ? toggling(alias, in: hidden) : hidden
    }
}
