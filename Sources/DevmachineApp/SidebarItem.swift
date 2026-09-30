import DevmachineCore
enum SidebarItem: Hashable {
    case session(alias: String, name: String)
    case localSession(name: String, path: String)

    var terminalKind: TerminalKind {
        switch self {
        case let .session(alias, name): return .remote(alias: alias, session: name)
        case let .localSession(name, path): return .local(session: name, path: path)
        }
    }
}

extension SidebarItem {
    /// The session this row stands for. A local session goes under the Local
    /// workspace's alias, keyed by its handle, as `SessionRef`s for it are.
    var sessionRef: SessionRef {
        switch self {
        case let .session(alias, name): return SessionRef(alias: alias, name: name)
        case let .localSession(handle, _): return SessionRef(alias: Workspace.local.alias, name: handle)
        }
    }
}

struct SessionRef: Hashable {
    let alias: String
    let name: String
}
