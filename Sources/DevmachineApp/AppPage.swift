enum AppPage: Hashable {
    case setup
    case stats
    case subdomains
    case customCommands
    case stack([SessionRef])
}
