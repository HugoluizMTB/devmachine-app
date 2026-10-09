struct DevmachineServices: Sendable {
    let workspaceSource: any WorkspaceSource
    let sessionSource: any SessionListSource
    let contextSource: any ContextSource

    init(
        workspaceSource: any WorkspaceSource = CLIWorkspaceSource(),
        sessionSource: any SessionListSource = CLIFirstSessionSource(),
        contextSource: any ContextSource = DemoMode.defaultContextSource()
    ) {
        self.workspaceSource = workspaceSource
        self.sessionSource = sessionSource
        self.contextSource = contextSource
    }
}
