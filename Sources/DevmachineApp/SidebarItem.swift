enum SidebarItem: Hashable {
    case session(alias: String, name: String)
    case opsShell

    var terminalKind: TerminalKind {
        switch self {
        case let .session(alias, name): return .remote(alias: alias, session: name)
        case .opsShell: return .opsShell
        }
    }
}

struct SessionRef: Hashable {
    let alias: String
    let name: String
}
