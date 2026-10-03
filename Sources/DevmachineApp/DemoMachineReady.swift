#if DEBUG
import DevmachineCore
import SwiftUI

/// Debug builds only. The machine readiness cards and onboarding's Install
/// CLI card, for the `DEVMACHINE_DEMO_WALK=machine-ready` capture. Prepare is
/// a job seeded into the corner at one moment; nothing runs.
@MainActor
enum DemoMachineReady {
    static let machine = "staging"

    static let workspaceMachines = [
        "acme": "main", "globex": "main", "initech": "backup", "umbrella": "staging",
    ]

    static func snapshot(cliVersion: String = "0.7.24", applied: Bool = false) -> ReadinessSnapshot {
        var snapshot = ReadinessSnapshot()
        snapshot.machines = ["main", "backup", "staging"]
        snapshot.declared = ["main": true, "backup": true, "staging": false]
        snapshot.lock = PackagesLock(appliedAt: applied ? "2" : "1", machines: [
            "main": [PackagesLock.Entry(name: MachinePrepare.package)],
            "backup": [PackagesLock.Entry(name: MachinePrepare.package)],
            "staging": applied ? [PackagesLock.Entry(name: MachinePrepare.package)] : [],
        ])
        if applied { snapshot.declared?["staging"] = true }
        snapshot.workspaceMachines = workspaceMachines
        snapshot.cliVersion = SemanticVersion(cliVersion)
        snapshot.sshAliasesWritten = true
        return snapshot
    }

    static func seed(_ store: MachineReadinessStore, model: AppModel, prepare: MachineJobPhase? = nil,
                     cliVersion: String = "0.7.24", outdated: Bool = false) {
        let done = prepare.map { if case .succeeded = $0 { return true } else { return false } } ?? false
        store.seedDemo(
            snapshot: snapshot(cliVersion: cliVersion, applied: done),
            observed: outdated
                ? ["backup": .outdated(detail: #"error: devmachine-app does not accept "stats". It accepts context"#)]
                : [:])
        if let prepare { store.seedDemoPrepare(machine, phase: prepare, log: log(prepare)) }
        model.seedDemoSessionProblem(.aliasMissing(alias: "initech-devmachine"), alias: "initech-devmachine")
    }

    static func card(_ store: MachineReadinessStore, model: AppModel, machine: String) -> some View {
        MachineReadinessCard(store: store, machine: machine)
            .environmentObject(model)
            .dmGlass(radius: DMRadius.panel, stroke: .white.opacity(0.15))
            .frame(width: 520)
            .padding(24)
            .background(Color.dmContentBg)
            .environment(\.colorScheme, .dark)
    }

    private static func log(_ phase: MachineJobPhase) -> [String] {
        let plan = [
            "$ devmachine packages add devmachine-app --machine staging --yes",
            "added devmachine-app to machine staging",
            "$ devmachine sync --machine staging --tags devmachine-app --yes",
            "staging: devmachine-app", "",
            "PLAY [devmachine] *************************************************", "",
            "TASK [Gathering Facts] ********************************************",
            "ok: [devmachine]", "",
            "TASK [devmachine-app : Create the config directory] ***************",
            "changed: [devmachine]",
        ]
        switch phase {
        case .failed:
            return plan + [
                #"fatal: [devmachine]: FAILED! => {"msg": "Permission denied"}"#,
                "error: 1 task(s) failed on staging: exit status 2",
            ]
        case .succeeded:
            return plan + ["", "staging: ok=3 changed=1 failed=0"]
        default:
            return plan
        }
    }
}

#endif
