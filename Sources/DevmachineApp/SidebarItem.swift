enum SidebarItem: Hashable {
    case session(alias: String, name: String)
    case operador
}

struct SessionRef: Hashable {
    let alias: String
    let name: String
}
