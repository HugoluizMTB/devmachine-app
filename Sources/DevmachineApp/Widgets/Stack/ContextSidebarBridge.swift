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

/// A session switch hands the widgets its context once its first read is
/// in, not on empty keys first. The git probe holds back only `repo` and
/// `branch`: the other keys go at once, and only widgets that read the
/// pending keys wait (`WidgetSourceController.setContext(_:pending:)`).
enum ContextPushGate {
    static let gitKeys: Set<String> = ["repo", "branch"]

    static func ready(status: ContextLoadStatus, hasState: Bool) -> Bool {
        !(status == .loading && !hasState)
    }

    /// Judged by the key the panel is about to probe, not the store's: on
    /// the render before the probe starts, the store still holds the old
    /// folder's answer.
    static func pendingGitKeys(needed: Bool, triggerKey: String?, answeredKey: String?) -> Set<String> {
        guard needed, let triggerKey, triggerKey != answeredKey else { return [] }
        return gitKeys
    }
}
