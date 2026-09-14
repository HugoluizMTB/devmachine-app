enum SidebarItem: Hashable {
    case session(alias: String, name: String)
    case opsShell
}

struct SessionRef: Hashable {
    let alias: String
    let name: String
}
