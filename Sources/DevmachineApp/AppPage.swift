enum AppPage: Hashable {
    case setup
    case stats
    case subdomains
    case stack([SessionRef])
    /// One machine's SSH host key, after ssh refused it.
    case hostKey(String)
    /// The Add machine wizard.
    case addMachine
}
