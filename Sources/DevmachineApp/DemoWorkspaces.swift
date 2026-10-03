#if DEBUG
import DevmachineCore
import Foundation

/// Debug builds only. The Workspaces page for `DEVMACHINE_DEMO_WALK=workspaces`:
/// the list, every flow's form and review, and a run in each state. The run
/// screens are seeded states: no CLI runs.
@MainActor
enum DemoWorkspaces {
    static let screens: [DemoSnapshots.Screen] = [
        .init(id: "workspaces-list", fileName: "130-workspaces-list.png", settleNanoseconds: 500_000_000),
        .init(id: "workspaces-new", fileName: "131-workspaces-new.png", settleNanoseconds: 400_000_000),
        .init(id: "workspaces-new-taken", fileName: "132-workspaces-new-taken.png", settleNanoseconds: 400_000_000),
        .init(id: "workspaces-review", fileName: "133-workspaces-review.png", settleNanoseconds: 400_000_000),
        .init(id: "workspaces-running", fileName: "134-workspaces-running.png", settleNanoseconds: 700_000_000),
        .init(id: "workspaces-failed", fileName: "135-workspaces-failed.png", settleNanoseconds: 600_000_000),
        .init(id: "workspaces-done", fileName: "136-workspaces-done.png", settleNanoseconds: 600_000_000),
        .init(id: "workspaces-edit", fileName: "137-workspaces-edit.png", settleNanoseconds: 400_000_000),
        .init(id: "workspaces-edit-review", fileName: "138-workspaces-edit-review.png", settleNanoseconds: 400_000_000),
        .init(id: "workspaces-forget", fileName: "139-workspaces-forget.png", settleNanoseconds: 400_000_000),
        .init(id: "workspaces-forget-refused", fileName: "140-workspaces-forget-refused.png",
              settleNanoseconds: 600_000_000),
        .init(id: "workspaces-destroy", fileName: "141-workspaces-destroy.png", settleNanoseconds: 400_000_000),
        .init(id: "workspaces-settings", fileName: "142-workspaces-settings.png", settleNanoseconds: 500_000_000),
    ]

    static let refusal = "acme publishes app.example.com through edge, which would keep serving it with nothing "
        + "left to take it off: `devmachine expose rm app.example.com` first"

    static func handles(_ id: String) -> Bool {
        screens.contains { $0.id == id }
    }

    static func prepare(_ id: String, model: AppModel) async {
        let store = WorkspacesStore.shared
        store.machines.seedDemo(DemoData.machinesSnapshot)
        model.workspaces = DemoData.workspaces
        store.runner.reset()
        store.close()
        if id == "workspaces-settings" {
            DemoSnapshots.setupInitialSection = .workspaces
            model.showPage(.setup)
            return
        }
        model.showPage(.workspaces)
        await store.load()
        try? await Task.sleep(nanoseconds: 150_000_000)
        switch id {
        case "workspaces-new":
            await startNew(store, name: "beta")
            store.flow?.togglePackage("claude-code")
        case "workspaces-new-taken":
            await startNew(store, name: "acme")
        case "workspaces-review":
            await startNew(store, name: "beta")
            store.flow?.togglePackage("claude-code")
            store.next()
        case "workspaces-running", "workspaces-failed", "workspaces-done":
            await startNew(store, name: "beta")
            store.flow?.togglePackage("claude-code")
            store.next()
            store.flow?.next()
            seedNewRun(store, id: id)
        case "workspaces-edit", "workspaces-edit-review":
            store.startEdit("acme")
            store.flow?.togglePackage("pi")
            store.flow?.addSetting()
            if let last = store.flow?.settings.indices.last {
                store.flow?.settings[last] = WorkspaceSetting(key: "pi.model", value: "fast")
            }
            if id == "workspaces-edit-review" { store.next() }
        case "workspaces-forget":
            store.startForget("initech")
        case "workspaces-forget-refused":
            store.startForget("acme")
            store.flow?.next()
            if let step = store.flow?.plan.first {
                store.runner.seedDemo(
                    statuses: [step.id: .failed], phase: .failed(step: step.id), problem: refusal,
                    lines: ["$ " + step.displayLine, "error: " + refusal])
            }
        case "workspaces-destroy":
            store.startDestroy("umbrella")
            store.flow?.typedName = "umbrella"
        default:
            break
        }
    }

    private static func startNew(_ store: WorkspacesStore, name: String) async {
        await store.startNew()
        store.flow?.draft.name = name
    }

    private static func seedNewRun(_ store: WorkspacesStore, id: String) {
        guard let plan = store.flow?.plan, plan.count == 2 else { return }
        let declared = [
            "$ " + plan[0].displayLine,
            "beta is in the configuration, on main, with the packages dev, zsh, mise, claude-code.",
            "The machine is untouched: `devmachine sync` is what creates the account.",
        ]
        let syncing = [
            "$ " + plan[1].displayLine,
            "PLAY [main] *******************************************************************",
            "TASK [workspace : create the account beta] ************************************",
            "changed: [main]",
            "TASK [zsh : make zsh the login shell] *****************************************",
        ]
        switch id {
        case "workspaces-running":
            store.runner.seedDemo(
                statuses: [plan[0].id: .done, plan[1].id: .running], phase: .running, lines: declared + syncing)
        case "workspaces-failed":
            store.runner.seedDemo(
                statuses: [plan[0].id: .done, plan[1].id: .failed], phase: .failed(step: plan[1].id),
                problem: "connecting to main (203.0.113.10:22): connection timed out",
                lines: declared + [
                    "$ " + plan[1].displayLine,
                    "error: connecting to main (203.0.113.10:22): connection timed out",
                ])
        default:
            store.runner.seedDemo(
                statuses: [plan[0].id: .done, plan[1].id: .done], phase: .succeeded,
                lines: declared + syncing + ["changed: [main]", "PLAY RECAP: main ok=41 changed=12 failed=0"])
        }
    }
}
#endif
