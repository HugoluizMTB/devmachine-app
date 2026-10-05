import Combine
import Foundation
import DevmachineCore

/// The selected machine's way to a DNS provider that answers: pick a
/// provider package, add it with its token, sync it, and keep saying so
/// until `dns providers` answers with a zone. Without one, `expose add`
/// only prints the record to create by hand.
@MainActor
final class DNSSetupStore: ObservableObject {
    @Published private(set) var machine: String?
    /// Every DNS provider package the packages release offers.
    @Published private(set) var catalog: [CLIPackage] = []
    /// The DNS provider packages the configuration asks for on `machine`.
    @Published private(set) var declared: [String]?
    @Published private(set) var answers: [DNSProviderAnswer]?
    @Published private(set) var jobs: [String: DNSSetupJob] = [:]
    /// The corner job each machine's sync runs as, which holds its log.
    @Published private(set) var syncing: [String: UUID] = [:]
    /// The provider whose token was saved last, for a short confirmation.
    @Published private(set) var savedToken: String?
    /// The provider whose zones were saved last.
    @Published private(set) var savedZones: String?

    /// A configuration change on this Mac (a package added): the packages
    /// list is read again.
    var onConfigurationChanged: () -> Void = {}
    /// A sync ended, well or not: `dns providers` is asked again, since
    /// only its answer says whether the machine is ready.
    var onSyncEnded: (String) -> Void = { _ in }
    /// `sync --tags` records only what it applied from CLI 0.7.24 on; an
    /// older CLI gets the commands to run in a terminal.
    var canRunSync: () -> Bool
    /// `machines edit --set` exists from CLI 0.7.27 on; an older CLI gets
    /// the `config.yml` snippet to add by hand.
    var canEditMachineSettings: () -> Bool

    private let service: CaddyService
    private var center: @MainActor () -> MachineJobCenter?
    private var runs: [String: UUID] = [:]
    private var jobsWatch: AnyCancellable?
    private weak var watchedCenter: MachineJobCenter?
    /// Packages this store added that `packages list` has not shown yet.
    private var added: [String: Set<String>] = [:]

    init(
        service: CaddyService,
        center: @escaping @MainActor () -> MachineJobCenter? = { AppModel.shared?.jobs },
        canRunSync: @escaping () -> Bool = { MachineReadinessStore.shared.canPrepareInApp },
        canEditMachineSettings: @escaping () -> Bool = {
            DNSProviderSetup.canEditMachineSettings(cliVersion: MachineReadinessStore.shared.snapshot?.cliVersion)
        }
    ) {
        self.service = service
        self.center = center
        self.canRunSync = canRunSync
        self.canEditMachineSettings = canEditMachineSettings
    }

    var state: DNSSetupState {
        guard let machine else { return .unknown }
        return DNSProviderSetup.evaluate(declared: declared, answers: answers, job: jobs[machine])
    }

    /// The provider the card is about once one is in the configuration, or
    /// the first one on offer before that.
    var suggestedProvider: String? {
        if case .notSynced(let provider, _) = state { return provider }
        return declared?.first ?? catalog.first?.name
    }

    /// The name the package's token is stored under.
    func secretName(_ package: String) -> String {
        catalog.first { $0.name == package }?.secretName ?? package
    }

    func isDeclared(_ package: String) -> Bool {
        declared?.contains(package) ?? false
    }

    /// `packages` nil means `packages list` could not be read: what was
    /// known about the same machine stays.
    func update(machine: String?, packages: [CLIPackage]?, answers: [DNSProviderAnswer]?) {
        let sameMachine = self.machine == machine
        if !sameMachine {
            self.machine = machine
            savedToken = nil
            savedZones = nil
        }
        if let packages {
            let catalog = CLIPackage.dnsProviders(in: packages)
            if self.catalog != catalog { self.catalog = catalog }
        }
        let declared: [String]?
        if let machine, let packages {
            let listed = CLIPackage.dnsProviders(in: packages).filter { $0.isInstalled(onMachine: machine) }.map(\.name)
            added[machine] = added[machine]?.subtracting(listed)
            declared = listed + (added[machine] ?? []).sorted()
        } else {
            declared = sameMachine ? self.declared : nil
        }
        if self.declared != declared { self.declared = declared }
        if self.answers != answers { self.answers = answers }
    }

    /// Adds `package` to the machine in the configuration, sets its zones
    /// when some were typed and the CLI can, and stores its token. All of it
    /// stays on this Mac; the machine changes only on sync. The zones come
    /// after the add: the CLI refuses a setting for a package not there.
    func install(_ package: String, token: String, zones: String = "") async {
        guard let machine, !isRunning(machine) else { return }
        let zoneList = zonesToSet(package, zones)
        guard zoneList != nil || zones.trimmingCharacters(in: .whitespaces).isEmpty || !canEditMachineSettings()
        else { return }
        let run = begin(machine, .install)
        if DemoMode.isActive { return fail(machine, run: run, step: .install, error: Self.demoRefusal) }
        let service = self.service
        let secret = secretName(package)
        if let failure = await perform({ try service.addPackage(package, machine: machine) }) {
            return fail(machine, run: run, step: .install, error: failure)
        }
        added[machine, default: []].insert(package)
        if !(declared ?? []).contains(package) { declared = (declared ?? []) + [package] }
        if let zoneList, let setting = DNSProviderCatalog.zonesSetting(for: package) {
            jobs[machine] = .running(.saveZones)
            if let failure = await perform({ try service.setZones(setting: setting, machine: machine, zones: zoneList) }) {
                onConfigurationChanged()
                return fail(machine, run: run, step: .saveZones, error: failure)
            }
        }
        jobs[machine] = .running(.saveToken)
        if let failure = await perform({ try service.setSecret(secret, value: token) }) {
            onConfigurationChanged()
            return fail(machine, run: run, step: .saveToken, error: failure)
        }
        guard runs[machine] == run else { return }
        jobs[machine] = .finished
        savedToken = package
        onConfigurationChanged()
    }

    /// Writes the zones the provider may manage into the machine's
    /// settings (`machines edit --set`); the next sync applies them.
    func saveZones(_ package: String, zones: String) async {
        guard let machine, !isRunning(machine), canEditMachineSettings(),
              let setting = DNSProviderCatalog.zonesSetting(for: package),
              let zoneList = zonesToSet(package, zones) else { return }
        let run = begin(machine, .saveZones)
        if DemoMode.isActive { return fail(machine, run: run, step: .saveZones, error: Self.demoRefusal) }
        let service = self.service
        if let failure = await perform({ try service.setZones(setting: setting, machine: machine, zones: zoneList) }) {
            return fail(machine, run: run, step: .saveZones, error: failure)
        }
        guard runs[machine] == run else { return }
        jobs[machine] = .finished
        savedZones = package
        onConfigurationChanged()
    }

    func saveToken(_ package: String, token: String) async {
        guard let machine, !isRunning(machine) else { return }
        let run = begin(machine, .saveToken)
        if DemoMode.isActive { return fail(machine, run: run, step: .saveToken, error: Self.demoRefusal) }
        let service = self.service
        let secret = secretName(package)
        if let failure = await perform({ try service.setSecret(secret, value: token) }) {
            return fail(machine, run: run, step: .saveToken, error: failure)
        }
        guard runs[machine] == run else { return }
        jobs[machine] = .finished
        savedToken = package
    }

    /// Applies only `package` on the machine, then delivers its token, as a
    /// job in the corner, which holds the log; the card says where it stands.
    @discardableResult
    func sync(_ package: String) -> UUID? {
        guard let machine, canRunSync(), !isRunning(machine), let center = center() else { return nil }
        if let previous = syncing[machine] { center.dismiss(previous) }
        let run = begin(machine, .sync)
        let plan = MachineJobPlan(
            machine: machine, title: "Sync \(package) on \(machine)",
            steps: DNSProviderSetup.syncSteps(package: package, machine: machine))
        watch(center)
        var started: UUID?
        let id = center.run(plan) { [weak self] outcome in
            guard let started else { return }
            self?.syncFinished(machine, run: run, job: started, outcome: outcome)
        }
        started = id
        syncing[machine] = id
        return id
    }

    /// A failed sync runs again in place, in the same corner job; false
    /// when that job is gone.
    @discardableResult
    func retrySync() -> Bool {
        guard let machine, let id = syncing[machine], let center = center(),
              case .failed = center.job(id)?.phase else { return false }
        center.retry(id)
        return true
    }

    /// Back to the card the failure replaced; a failed sync leaves the
    /// corner with it.
    func dismissFailure() {
        guard let machine else { return }
        if let id = syncing[machine] { center()?.dismiss(id) }
        syncing[machine] = nil
        jobs[machine] = nil
        runs[machine] = nil
    }

    private func syncFinished(_ machine: String, run: UUID, job: UUID, outcome: MachineJobOutcome) {
        guard runs[machine] == run else { return }
        switch outcome {
        case .succeeded:
            jobs[machine] = .finished
        case .failed:
            let lines = center()?.job(job)?.log.lines ?? []
            var cause = "devmachine stopped."
            if case let .failed(reason) = center()?.job(job)?.phase { cause = reason }
            jobs[machine] = .failed(.sync, cause: cause, details: lines.isEmpty ? cause : lines.joined(separator: "\n"))
        case .cancelled:
            jobs[machine] = nil
            syncing[machine] = nil
        }
        onSyncEnded(machine)
    }

    private func watch(_ center: MachineJobCenter) {
        guard watchedCenter !== center else { return }
        watchedCenter = center
        jobsWatch = center.$jobs.sink { [weak self] jobs in
            MainActor.assumeIsolated { self?.followJobs(jobs) }
        }
    }

    /// A failed sync retried in the corner is running again; one dismissed
    /// there takes the card's failure with it.
    private func followJobs(_ centerJobs: [MachineJob]) {
        for (machine, id) in syncing {
            guard let job = centerJobs.first(where: { $0.id == id }) else {
                syncing[machine] = nil
                if case .failed(.sync, _, _) = jobs[machine] {
                    jobs[machine] = nil
                    runs[machine] = nil
                }
                continue
            }
            switch job.phase {
            case .pending, .queued, .running:
                if case .failed(.sync, _, _) = jobs[machine] { jobs[machine] = .running(.sync) }
            case .succeeded, .failed, .cancelled:
                break
            }
        }
    }

    private static let demoRefusal = DevmachineCLIError.commandFailed(
        "Demo mode never changes a configuration or a secret.")

    /// Nil when nothing usable was typed, or the CLI cannot set it.
    private func zonesToSet(_ package: String, _ text: String) -> [String]? {
        guard canEditMachineSettings(), DNSProviderCatalog.zonesSetting(for: package) != nil,
              let zones = DNSProviderCatalog.zones(from: text), !zones.isEmpty else { return nil }
        return zones
    }

    private func isRunning(_ machine: String) -> Bool {
        if case .running = jobs[machine] { return true }
        return false
    }

    private func begin(_ machine: String, _ step: DNSSetupStep) -> UUID {
        let run = UUID()
        runs[machine] = run
        jobs[machine] = .running(step)
        savedToken = nil
        savedZones = nil
        return run
    }

    private func perform(_ work: @escaping @Sendable () throws -> Void) async -> Error? {
        await Task.detached { () -> Error? in
            do {
                try work()
                return nil
            } catch {
                return error
            }
        }.value
    }

    private func fail(_ machine: String, run: UUID, step: DNSSetupStep, error: Error) {
        guard runs[machine] == run else { return }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let cause = FailureCause(message: message)?.summary ?? message
        jobs[machine] = .failed(step, cause: cause, details: message)
    }

    #if DEBUG
    /// Demo walks only: a fixed state, with no real CLI behind it.
    func seedDemo(
        machine: String, packages: [CLIPackage], answers: [DNSProviderAnswer]?, job: DNSSetupJob? = nil
    ) {
        canRunSync = { true }
        canEditMachineSettings = { true }
        update(machine: machine, packages: packages, answers: answers)
        jobs[machine] = job
    }

    /// Demo walks only: syncs run on `center`, whose runner never reaches a CLI.
    func seedDemoCenter(_ center: MachineJobCenter) {
        self.center = { center }
    }

    func clearDemoJobs() {
        jobs = [:]
        syncing = [:]
        runs = [:]
        added = [:]
        savedToken = nil
        savedZones = nil
    }
    #endif
}
