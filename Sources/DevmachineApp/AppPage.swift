enum AppPage: Hashable {
    case setup
    case stats
    case subdomains
    case stack([SessionRef])
    /// The Add machine wizard.
    case addMachine
}
