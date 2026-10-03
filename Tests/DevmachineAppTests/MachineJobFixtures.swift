import Foundation
import DevmachineCore
@testable import DevmachineApp

/// Machine jobs in each phase, on the fixture machine `main`, for the
/// component gallery and the fit checks.
enum MachineJobFixtures {
    static let plan = MachineJobPlan(
        machine: "main", title: "Sync main",
        steps: [["sync", "--machine", "main", "--tags", "docker,node", "--yes"]])

    static func job(_ phase: MachineJobPhase, expanded: Bool = false) -> MachineJob {
        var log = JobLog()
        log.append(contentsOf: [
            "$ devmachine sync --machine main --tags docker,node --yes",
            "TASK [docker : Install the Docker packages] *********************************",
            "\u{1B}[0;33mchanged: [main]\u{1B}[0m",
            "TASK [node : Install Node with mise] ********************************************",
        ])
        return MachineJob(
            id: UUID(), plan: plan, phase: phase, log: phase == .pending ? JobLog() : log,
            request: SyncRequest(machine: "main", tags: ["docker", "node"], reasons: ["docker added", "node added"]),
            expanded: expanded, currentCommand: "devmachine sync --machine main --tags docker,node --yes")
    }

    static var failed: MachineJob {
        job(.failed(cause: "main could not be reached over ssh."))
    }

    static var succeeded: MachineJob {
        job(.succeeded(SyncSummary(ok: 42, changed: 3, failed: 0)))
    }

    static var actions: MachineJobToast.Actions {
        MachineJobToast.Actions(
            start: { _ in }, later: {}, cancel: {}, retry: {}, dismiss: {}, toggleLog: {}, openFullLog: {})
    }
}
