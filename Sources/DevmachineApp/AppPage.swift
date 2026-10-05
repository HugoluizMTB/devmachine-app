enum AppPage: Hashable {
    case setup
    case stats
    case subdomains
    case stack([SessionRef])
    /// The Add machine wizard.
    case addMachine
    /// Every workspace by machine, and the flows that add, change, forget
    /// and destroy one.
    case workspaces
}
