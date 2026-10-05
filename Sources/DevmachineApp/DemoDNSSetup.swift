#if DEBUG
import Foundation
import DevmachineCore

/// Demo mode's sync for the DNS setup walk: it prints an invented log and
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

/// The DNS setup walk (`DEVMACHINE_DEMO_WALK=dns-setup`): the Subdomains
/// page on a server with no provider, one not synced, one that sees no
/// zone, a sync running, failed and done. The sync runs on a demo center
/// whose runner is `DemoDNSSyncRunner`; the corner shows a copy of its jobs.
@MainActor
enum DemoDNSWalk {
    static func prepare(_ id: String, store: CaddyStore, model: AppModel) async {
        store.dnsSetup.clearDemoJobs()
        model.jobs.seedDemo([])
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
            await sync(store, model: model, untilDone: false)
        case "dns-failed":
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            DemoDNSSyncRunner.outcome = .fails
            await sync(store, model: model, untilDone: true)
        case "dns-ready":
            await sync(store, model: model, untilDone: true)
        default:
            break
        }
    }

    /// The walk leaves the page as every other screen expects it.
    static func reset() {
        DemoData.dnsScenario = .ready
        DemoDNSSyncRunner.outcome = .succeeds
        AppModel.shared?.jobs.seedDemo([])
    }

    private static func sync(_ store: CaddyStore, model: AppModel, untilDone: Bool) async {
        let center = MachineJobCenter(runner: DemoDNSSyncRunner(), successSeconds: 60)
        store.dnsSetup.seedDemoCenter(center)
        guard let id = store.dnsSetup.sync("hostinger") else { return }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let job = center.job(id) else { break }
            if case .running = job.phase, !untilDone, !job.log.lines.isEmpty { break }
            if case .succeeded = job.phase { break }
            if case .failed = job.phase { break }
        }
        model.jobs.seedDemo(center.jobs.map { job in
            var shown = job
            shown.expanded = true
            return shown
        })
    }
}
#endif
