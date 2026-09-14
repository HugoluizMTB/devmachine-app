enum SidebarItem: Hashable {
    case session(alias: String, name: String)
    case localSession(name: String)

    var terminalKind: TerminalKind {
        switch self {
        case let .session(alias, name): return .remote(alias: alias, session: name)
        case let .localSession(name): return .local(session: name)
        }
    }
}

struct SessionRef: Hashable {
    let alias: String
    let name: String
}
