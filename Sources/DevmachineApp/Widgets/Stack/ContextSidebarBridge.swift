import DevmachineCore

/// Maps what the app knows about the selected session to the
/// context-sidebar's keys. Unknown stays empty, never a guess.
enum ContextBridge {
    static func facts(
        selection: SidebarItem?, workspaces: [Workspace], machineForWorkspace: (String) -> String?,
        selfMachine: String?, state: ContextState?, git: ContextGitStatus?
    ) -> SessionContextFacts {
        var facts = SessionContextFacts(
            path: state?.cwd ?? "", repo: git?.repo ?? "", branch: git?.branch ?? "",
            harness: state?.harness?.rawValue ?? "")
        switch selection {
        case let .session(alias, name)?:
            facts.session = name
            facts.workspace = workspaces.first { $0.alias == alias }?.name ?? ""
            facts.machine = facts.workspace.isEmpty ? "" : machineForWorkspace(facts.workspace) ?? ""
        case let .localSession(name, path)?:
            facts.session = name
            facts.machine = selfMachine ?? ""
            if facts.path.isEmpty { facts.path = path }
        case nil:
            break
        }
        return facts
    }
}

/// A session switch hands the widgets its context once, whole: not while
/// its first read or git probe is still out, which would run each widget
/// on empty keys first and flash an approval card for them.
enum ContextPushGate {
    static func ready(status: ContextLoadStatus, hasState: Bool, gitPending: Bool) -> Bool {
        let firstReadOut = status == .loading && !hasState
        return !firstReadOut && !gitPending
    }
}
