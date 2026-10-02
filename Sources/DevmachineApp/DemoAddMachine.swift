#if DEBUG
import DevmachineCore
import Foundation

/// Debug builds only. Settings → Machines, the sidebar with no machine, and
/// every step of the Add machine wizard, for `DEVMACHINE_DEMO_WALK=machines`.
/// The run screens are seeded states: nothing is typed and no CLI runs.
@MainActor
enum DemoAddMachine {
    static let screens: [DemoSnapshots.Screen] = [
        .init(id: "machines-settings", fileName: "100-machines-settings.png", settleNanoseconds: 500_000_000),
        .init(id: "add-machine-kind", fileName: "101-add-machine-kind.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-details", fileName: "102-add-machine-details.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-password", fileName: "103-add-machine-password.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-packages", fileName: "104-add-machine-packages.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-review", fileName: "105-add-machine-review.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-local-review", fileName: "106-add-machine-local-review.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-running", fileName: "107-add-machine-running.png", settleNanoseconds: 900_000_000),
        .init(id: "add-machine-failed", fileName: "108-add-machine-failed.png", settleNanoseconds: 600_000_000),
        .init(id: "add-machine-done", fileName: "109-add-machine-done.png", settleNanoseconds: 600_000_000),
        .init(id: "no-machines-home", fileName: "110-no-machines-home.png", settleNanoseconds: 700_000_000),
        .init(id: "no-machines-kind", fileName: "111-no-machines-kind.png", settleNanoseconds: 400_000_000),
        .init(id: "no-machines-packages", fileName: "112-no-machines-packages.png", settleNanoseconds: 400_000_000),
        .init(id: "no-machines-review", fileName: "113-no-machines-review.png", settleNanoseconds: 400_000_000),
    ]

    static func handles(_ id: String) -> Bool {
        screens.contains { $0.id == id }
    }

    static func prepare(_ id: String, model: AppModel) async {
        let state = AddMachineModel.shared
        let machines = MachinesStore.shared
        machines.seedDemo(id.hasPrefix("no-machines") ? DemoData.noMachinesSnapshot : DemoData.machinesSnapshot)
        model.workspaces = id.hasPrefix("no-machines") ? [] : DemoData.workspaces
        state.startOver()
        switch id {
        case "machines-settings":
            DemoSnapshots.setupInitialSection = .machines
            model.showPage(.setup)
            return
        case "no-machines-home":
            return
        default:
            break
        }
        model.showPage(.addMachine)
        try? await Task.sleep(nanoseconds: 150_000_000)
        state.startOver()
        switch id {
        case "add-machine-details":
            fillServer(state)
        case "add-machine-password":
            fillServer(state)
            state.wizard.draft.login = .password
            state.wizard.draft.fingerprint = ""
        case "add-machine-packages":
            fillServer(state)
            state.wizard.next()
            state.wizard.togglePackage("docker")
            state.wizard.togglePackage("tailscale")
        case "add-machine-review":
            fillServer(state)
            state.wizard.next()
            state.wizard.togglePackage("docker")
            state.wizard.next()
        case "no-machines-packages":
            fillServer(state)
            state.wizard.next()
        case "no-machines-review":
            fillServer(state)
            state.wizard.next()
            state.wizard.next()
        case "add-machine-local-review":
            state.wizard.choose(.localVM)
            state.wizard.draft.name = "lab"
            state.wizard.draft.workspace = "acme-lab"
            state.wizard.next()
            state.wizard.next()
        case "add-machine-running", "add-machine-failed", "add-machine-done":
            fillServer(state)
            state.wizard.next()
            state.wizard.togglePackage("docker")
            state.wizard.next()
            state.wizard.next()
            seedRun(state, id: id)
        default:
            break
        }
    }

    private static func fillServer(_ state: AddMachineModel) {
        state.wizard.choose(.server)
        state.wizard.draft.name = "backup"
        state.wizard.draft.address = "203.0.113.20"
        state.wizard.draft.workspace = "beta"
        state.wizard.draft.keyFile = "~/.ssh/id_ed25519"
        state.wizard.draft.fingerprint = "256 \(DemoData.addMachineFingerprint) root@backup (ED25519)"
    }

    private static func seedRun(_ state: AddMachineModel, id: String) {
        let plan = state.wizard.plan
        var statuses: [String: MachineStepRunner.StepStatus] = [:]
        switch id {
        case "add-machine-running":
            statuses[plan[0].id] = .done
            statuses[plan[1].id] = .running
            state.runner.seedDemo(statuses: statuses, phase: .running)
        case "add-machine-failed":
            statuses[plan[0].id] = .done
            statuses[plan[1].id] = .done
            statuses[plan[2].id] = .failed
            state.runner.seedDemo(
                statuses: statuses, phase: .failed(step: plan[2].id),
                problem: "\(plan[2].displayLine) ended with an error. The terminal shows what it said.")
        default:
            for step in plan { statuses[step.id] = .done }
            state.runner.seedDemo(statuses: statuses, phase: .succeeded)
        }
    }
}
#endif
