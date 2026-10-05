import DevmachineCore
enum AppPage: Hashable {
    case setup
    case stats
    case subdomains
    case stack([SessionRef])
    /// The Add machine wizard.
    case addMachine
    /// The Operator's first open: which installed harness to start it in.
    case operatorChooser([HarnessID])
}
