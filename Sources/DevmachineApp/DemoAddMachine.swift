#if DEBUG
import DevmachineCore
import Foundation

/// Debug builds only. Settings → Machines, the sidebar with no machine, and
/// every step of the Add machine wizard, for `DEVMACHINE_DEMO_WALK=machines`.
/// The run screens are seeded states: nothing is typed and no CLI runs. The
/// `legacy-` screens are a CLI older than `MachineUnattendedAdd`, which
/// still adds through a terminal.
@MainActor
enum DemoAddMachine {
    static let screens: [DemoSnapshots.Screen] = [
        .init(id: "machines-settings", fileName: "100-machines-settings.png", settleNanoseconds: 500_000_000),
        .init(id: "add-machine-kind", fileName: "101-add-machine-kind.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-details", fileName: "102-add-machine-details.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-password", fileName: "103-add-machine-password.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-agent-key", fileName: "104-add-machine-agent-key.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-packages", fileName: "105-add-machine-packages.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-review", fileName: "106-add-machine-review.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-local-review", fileName: "107-add-machine-local-review.png", settleNanoseconds: 400_000_000),
        .init(id: "add-machine-running", fileName: "108-add-machine-running.png", settleNanoseconds: 900_000_000),
        .init(id: "add-machine-failed", fileName: "109-add-machine-failed.png", settleNanoseconds: 600_000_000),
        .init(id: "add-machine-done", fileName: "110-add-machine-done.png", settleNanoseconds: 600_000_000),
        .init(id: "no-machines-home", fileName: "111-no-machines-home.png", settleNanoseconds: 700_000_000),
        .init(id: "no-machines-kind", fileName: "112-no-machines-kind.png", settleNanoseconds: 400_000_000),
        .init(id: "no-machines-details", fileName: "113-no-machines-details.png", settleNanoseconds: 400_000_000),
        .init(id: "no-machines-packages", fileName: "114-no-machines-packages.png", settleNanoseconds: 400_000_000),
        .init(id: "no-machines-review", fileName: "115-no-machines-review.png", settleNanoseconds: 400_000_000),
        .init(id: "legacy-review", fileName: "116-legacy-review.png", settleNanoseconds: 400_000_000),
        .init(id: "legacy-running", fileName: "117-legacy-running.png", settleNanoseconds: 900_000_000),
        .init(id: "cli-socket-home", fileName: "118-cli-socket-home.png", settleNanoseconds: 700_000_000),
        .init(id: "cli-socket-stats", fileName: "119-cli-socket-stats.png", settleNanoseconds: 700_000_000),
        .init(id: "add-machine-local-details", fileName: "120-add-machine-local-details.png",
              settleNanoseconds: 400_000_000),
        .init(id: "add-machine-local-unsized", fileName: "121-add-machine-local-unsized.png",
              settleNanoseconds: 400_000_000),
    ]

    /// What an older CLI printed for every machine under a long home folder.
    static let socketPathError = "unix_listener: path \"/Users/alice/Library/Caches/devmachine/cm/"
        + "4f1c0de7a2b94c3d8e5f6a7b8c9d0e1f.k2j4h6\" too long for Unix domain socket"

    static func handles(_ id: String) -> Bool {
        screens.contains { $0.id == id }
    }

    static func prepare(_ id: String, model: AppModel, stats: StatsStore) async {
        let state = AddMachineModel.shared
        let machines = MachinesStore.shared
        let hasMachines = !id.hasPrefix("no-machines")
        let legacy = id.hasPrefix("legacy")
        machines.seedDemo(
            legacy ? DemoData.legacyMachinesSnapshot
                : id == "add-machine-local-unsized" ? DemoData.unsizedMachinesSnapshot
                : (hasMachines ? DemoData.machinesSnapshot : DemoData.noMachinesSnapshot))
        model.workspaces = hasMachines ? DemoData.workspaces : []
        stats.seedDemo(hasMachines: hasMachines)
        state.startOver()
        switch id {
        case "machines-settings":
            DemoSnapshots.setupInitialSection = .machines
            model.showPage(.setup)
            return
        case "no-machines-home":
            return
        case "cli-socket-home", "cli-socket-stats":
            stats.seedDemoFailure("staging", error: socketPathError)
            if id == "cli-socket-stats" {
                stats.select("staging")
                model.showPage(.stats)
            }
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
            await state.scan()
        case "add-machine-password":
            fillServer(state)
            state.wizard.draft.login = .password
            state.wizard.draft.password = SecretText("demo-password")
            state.wizard.draft.fingerprint = ""
            await state.scan()
        case "add-machine-agent-key":
            fillServer(state)
            state.wizard.draft.keySource = .agent
            state.wizard.draft.fingerprint = ""
            await state.loadAgentKeys()
            state.wizard.draft.agentKey = DemoData.addMachineAgentKeys[0].fingerprint
            await state.scan()
        case "add-machine-packages", "no-machines-packages":
            fillServer(state)
            state.wizard.next()
        case "add-machine-review":
            fillPasswordServer(state)
            state.wizard.next()
            state.wizard.next()
        case "no-machines-details":
            fillServer(state)
            state.wizard.draft.domain = "example.com"
            await state.scan()
        case "no-machines-review":
            fillServer(state)
            state.wizard.draft.domain = "example.com"
            state.wizard.next()
            state.wizard.next()
        case "add-machine-local-details", "add-machine-local-unsized":
            state.wizard.choose(.localVM)
            state.wizard.draft.name = "lab"
            state.wizard.draft.workspace = "acme-lab"
        case "add-machine-local-review":
            state.wizard.choose(.localVM)
            state.wizard.draft.name = "lab"
            state.wizard.draft.workspace = "acme-lab"
            state.wizard.next()
            state.wizard.next()
        case "legacy-review":
            fillServer(state)
            state.wizard.draft.login = .password
            state.wizard.next()
            state.wizard.next()
        case "add-machine-running", "add-machine-failed", "add-machine-done", "legacy-running":
            if id == "legacy-running" { fillServer(state) } else { fillPasswordServer(state) }
            state.wizard.next()
            state.wizard.next()
            state.wizard.next()
            seedRun(state, id: id)
        default:
            break
        }
    }

    private static func fillPasswordServer(_ state: AddMachineModel) {
        fillServer(state)
        state.wizard.draft.login = .password
        state.wizard.draft.password = SecretText("demo-password")
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
        let output = DemoData.addMachineOutput
        var statuses: [String: MachineStepRunner.StepStatus] = [:]
        switch id {
        case "legacy-running":
            statuses[plan[0].id] = .done
            statuses[plan[1].id] = .running
            state.runner.seedDemo(statuses: statuses, phase: .running)
        case "add-machine-running":
            statuses[plan[0].id] = .done
            statuses[plan[1].id] = .running
            state.runner.seedDemo(statuses: statuses, phase: .running, lines: output)
        case "add-machine-failed":
            statuses[plan[0].id] = .failed
            state.runner.seedDemo(
                statuses: statuses, phase: .failed(step: plan[0].id),
                problem: "connecting to 203.0.113.20:22: connection timed out",
                lines: Array(output.prefix(1)) + [
                    "Error: connecting to 203.0.113.20:22: connection timed out",
                ])
        default:
            for step in plan { statuses[step.id] = .done }
            state.runner.seedDemo(
                statuses: statuses, phase: .succeeded,
                lines: output + ["$ devmachine workspaces new beta --machine backup --yes", "added workspace beta",
                                 "$ devmachine sync --machine backup --yes", "backup is in sync"])
        }
    }
}
#endif
