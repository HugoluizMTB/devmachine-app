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

struct SessionRef: Hashable {
    let alias: String
    let name: String
}
