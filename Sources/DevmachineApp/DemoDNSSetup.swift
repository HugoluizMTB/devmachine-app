import Foundation
import DevmachineCore

/// Demo mode's sync for the DNS setup card: it prints an invented log and
/// never starts a process, so no demo click can reach a CLI or a machine.
struct DemoDNSSyncRunner: MachineJobRunning {
    enum Outcome: Sendable {
        case succeeds, fails, holds
    }

    nonisolated(unsafe) static var outcome = Outcome.succeeds

    func run(arguments: [String], output: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        let outcome = Self.outcome
        if arguments.first == "credentials" {
            output("main: hostinger written to ~/.config/devmachine/env/hostinger.env")
            if outcome == .succeeds { await MainActor.run { DemoData.dnsScenario = .ready } }
            return 0
        }
        for line in [
            "main: hostinger", "", "PLAY [devmachine] *************************************************", "",
            "TASK [hostinger : Install the provider entrypoint] ****************", "changed: [devmachine]",
        ] {
            output(line)
        }
        switch outcome {
        case .holds:
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return 0
        case .fails:
            output("fatal: [devmachine]: FAILED! => {\"msg\": \"Permission denied\"}")
            output("error: 1 task(s) failed on main: exit status 2")
            return 1
        case .succeeds:
            output("main: ok=2 changed=1 failed=0")
            return 0
        }
    }
}

#if DEBUG
/// The DNS setup walk (`DEVMACHINE_DEMO_WALK=dns-setup`): the Subdomains
/// page on a server with no provider, one not synced, one that sees no
/// zone, a sync running, failed and done. The sync is `DemoDNSSyncRunner`.
@MainActor
enum DemoDNSWalk {
    static func prepare(_ id: String, store: CaddyStore, model: AppModel) async {
        store.dnsSetup.clearDemoJobs()
        DemoDNSSyncRunner.outcome = .succeeds
        switch id {
        case "dns-none": DemoData.dnsScenario = .noneInstalled
        case "dns-no-zones": DemoData.dnsScenario = .noZones
        default: DemoData.dnsScenario = .notSynced
        }
        DemoSnapshots.subdomainsInitialTab = .sites
        model.showPage(.subdomains)
        try? await Task.sleep(nanoseconds: 300_000_000)
        switch id {
        case "dns-syncing":
            DemoDNSSyncRunner.outcome = .holds
            Task { await store.dnsSetup.sync("hostinger") }
        case "dns-failed":
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            DemoDNSSyncRunner.outcome = .fails
            await store.dnsSetup.sync("hostinger")
        case "dns-ready":
            await store.dnsSetup.sync("hostinger")
        default:
            break
        }
    }

    /// The walk leaves the page as every other screen expects it.
    static func reset() {
        DemoData.dnsScenario = .ready
        DemoDNSSyncRunner.outcome = .succeeds
    }
}
#endif
