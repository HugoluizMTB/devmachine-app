import DevmachineCore
import Foundation
import os

struct SourceRunners: Sendable {
    var command: any SourceRunner
    var url: any SourceRunner
    var prompt: any SourceRunner
    var session: any SourceRunner
    var launcher: any ProcessLaunching
    var environment: SourceRunEnvironment

    func runner(for source: WidgetSource) -> (any SourceRunner)? {
        switch source {
        case .command: return command
        case .url: return url
        case .prompt: return prompt
        case .session: return session
        case .provider: return nil
        }
    }
}

struct SourceWidgetEntry: Equatable {
    let id: String
    let source: ResolvedSource
    let isVisible: Bool
}

/// Runs a board's command, url, prompt and session widgets. A widget poll
/// is the widget's own content, never a machine job card.
@MainActor
final class WidgetSourceController: ObservableObject {
    @Published private(set) var states: [String: SourceWidgetState] = [:]
    @Published private(set) var approvals: WidgetApprovals

    private enum Outcome {
        case result(SourceRunResult)
        case failure(SourceError)
        case cancelled
    }

    private var schedule = SourceSchedule()
    private var entries: [String: SourceWidgetEntry] = [:]
    private var hashes: [String: Result<String?, SourceError>] = [:]
    private var streams: [String: StreamSession] = [:]
    private var heldStreams: Set<String> = []
    private var histories: [String: SparklineHistory] = [:]
    private var runs: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    private var timer: Timer?
    private var isStarted = false
    private let runners: SourceRunners
    private let approvalsFile: WidgetApprovalsFile
    private let historyStore: SparklineHistoryStore
    private let surface: String
    private(set) var context: [String: String]
    private let contextKeys: Set<String>
    private let isDemo: Bool
    private let startsTimer: Bool
    private let now: () -> Date
    private nonisolated static let log = Logger(subsystem: "app.devmachine.mac", category: "widgets")
    private nonisolated static let historyQueue = DispatchQueue(label: "app.devmachine.mac.widget-history", qos: .utility)

    init(
        runners: SourceRunners, approvalsFile: WidgetApprovalsFile = WidgetApprovalsFile(),
        historyStore: SparklineHistoryStore = SparklineHistoryStore(), surface: String = DefaultBoard.surface,
        context: [String: String] = [:], isDemo: Bool = DemoMode.isActive, startsTimer: Bool = true,
        now: @escaping () -> Date = Date.init, contract: WidgetContract = .current
    ) {
        self.runners = runners
        self.approvalsFile = approvalsFile
        self.historyStore = historyStore
        self.surface = surface
        let keys = Set(contract.surfaces[surface]?.context.keys.map { $0 } ?? [])
        contextKeys = keys
        self.context = context.filter { keys.contains($0.key) }
        self.isDemo = isDemo
        self.startsTimer = startsTimer
        self.now = now
        approvals = approvalsFile.load()
    }

    var isDemoMode: Bool { isDemo }
    var isTicking: Bool { timer != nil }

    func state(_ id: String) -> SourceWidgetState { states[id] ?? SourceWidgetState() }

    func history(_ id: String) -> [SparklinePoint] { histories[id]?.points ?? [] }

    /// A source whose approval hash cannot be built waits with an empty hash,
    /// which no decision can allow; its state carries the refusal.
    func approvalState(_ id: String) -> ApprovalState {
        guard let entry = entries[id] else { return .notNeeded }
        guard entry.source.needsApproval else { return .notNeeded }
        guard case let .success(hash) = hashes[id] else { return .waiting(hash: "") }
        return approvals.state(needsApproval: true, hash: hash)
    }

    func update(_ next: [SourceWidgetEntry]) {
        let old = entries
        entries = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for (id, entry) in old where entries[id]?.source != entry.source {
            cancelRun(id)
            stopStream(id)
            heldStreams.remove(id)
            hashes[id] = nil
            states[id] = nil
            if entries[id] == nil { histories[id] = nil }
        }
        for entry in next where hashes[entry.id] == nil {
            hashes[entry.id] = approvalHash(entry)
        }
        for (id, entry) in entries where !entry.isVisible {
            stopStream(id)
            heldStreams.remove(id)
        }
        for entry in next where entry.source.view.kind == "sparkline" && histories[entry.id] == nil {
            histories[entry.id] = historyStore.load(surface: surface, id: entry.id)
        }
        replaceJobs()
        tick()
    }

    /// A new session (or selection) for this board's area. Only widgets that
    /// read a changed key start over; what they showed belonged to the other
    /// session, so it goes too.
    func setContext(_ next: [String: String]) {
        let filtered = next.filter { contextKeys.contains($0.key) }
        guard filtered != context else { return }
        objectWillChange.send()
        let old = context
        context = filtered
        for (id, entry) in entries where entry.source.values(context: old) != entry.source.values(context: filtered) {
            cancelRun(id)
            stopStream(id)
            heldStreams.remove(id)
            if states[id] != nil { states[id] = nil }
            hashes[id] = approvalHash(entry)
        }
        replaceJobs()
        tick()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let stored = approvalsFile.load()
        if stored != approvals {
            approvals = stored
            schedule.resumeAll()
            replaceJobs()
        }
        if startsTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard let self else { return timer.invalidate() }
                MainActor.assumeIsolated { self.tick() }
            }
        }
        tick()
    }

    func stop() {
        isStarted = false
        timer?.invalidate()
        timer = nil
        for id in Array(runs.keys) { cancelRun(id) }
        for id in Array(streams.keys) { stopStream(id) }
        heldStreams.removeAll()
    }

    func tick() {
        guard isStarted else { return }
        for id in schedule.due(now: now()) { run(id) }
        syncStreams()
    }

    func runNow(_ id: String) {
        guard isStarted, schedule.canRunNow(id), let entry = entries[id], entry.isVisible else { return }
        guard entry.source.every == .continuous else { return run(id) }
        heldStreams.remove(id)
        if streams[id] == nil { startStream(id) }
    }

    /// The card reads what the hash covers: the source filled with this
    /// area's context, the same way the run fills it.
    func approvalPrompt(for source: ResolvedSource) -> ApprovalPrompt {
        ApprovalPrompt(source, context: context)
    }

    func webAddress(for source: ResolvedSource) -> Result<URL, SourceError> {
        Result { try URLSourceRunner.address(of: source, context: context) }
            .mapError { $0 as? SourceError ?? .unreadable($0.localizedDescription) }
    }

    /// A decision counts only for the hash the card showed: if the context
    /// moved on since, the card redraws and asks for the new values.
    func approve(_ id: String, hash: String) { decide(.allowed, id, shown: hash) }
    func deny(_ id: String, hash: String) { decide(.denied, id, shown: hash) }

    private func decide(_ decision: ApprovalDecision, _ id: String, shown: String) {
        guard let entry = entries[id], entry.source.needsApproval,
              case let .success(hash?) = hashes[id], !hash.isEmpty, hash == shown
        else { return }
        approvals.record(decision, hash: hash, summary: approvalPrompt(for: entry.source).summary, at: now())
        do {
            try approvalsFile.save(approvals)
        } catch {
            Self.log.error("saving widget approvals failed: \(error.localizedDescription, privacy: .public)")
        }
        if decision == .denied {
            cancelRun(id)
            stopStream(id)
        }
        schedule.resumeAll()
        replaceJobs()
        tick()
    }

    private func approvalHash(_ entry: SourceWidgetEntry) -> Result<String?, SourceError> {
        guard entry.source.needsApproval else { return .success(nil) }
        do {
            return .success(try ApprovalSubject.hash(for: entry.source, context: context))
        } catch {
            let refusal = SourceError.refused(error.localizedDescription)
            var state = self.state(entry.id)
            state.error = refusal
            states[entry.id] = state
            return .failure(refusal)
        }
    }

    private func replaceJobs() {
        schedule.replaceJobs(entries.values.compactMap(job(for:)))
    }

    private func job(for entry: SourceWidgetEntry) -> SourceJob? {
        guard entry.source.view.kind != "web", runners.runner(for: entry.source.source) != nil else { return nil }
        let refused = if case .failure = hashes[entry.id] { true } else { false }
        let runnable = approvalState(entry.id).canRun && !refused && !isDemo
        return SourceJob(
            instanceID: entry.id, source: entry.source, isRunnable: runnable, isVisible: entry.isVisible,
            signature: String(describing: entry.source) + "|" + Self.contextSignature(entry.source.readContext(context)))
    }

    private static func contextSignature(_ context: [String: String]) -> String {
        context.keys.sorted().map { "\($0)=\(context[$0] ?? "")" }.joined(separator: "\u{1F}")
    }

    private func request(_ id: String, _ entry: SourceWidgetEntry) -> SourceRunRequest {
        SourceRunRequest(instanceID: id, source: entry.source, context: context, approvals: approvals)
    }

    private func run(_ id: String) {
        guard let entry = entries[id], let runner = runners.runner(for: entry.source.source) else { return }
        schedule.begin(id, at: now())
        var state = self.state(id)
        state.isRunning = true
        states[id] = state
        let request = request(id, entry)
        let token = UUID()
        let task = Task { [weak self] in
            let outcome: Outcome
            do {
                outcome = .result(try await runner.fetch(request))
            } catch is CancellationError {
                outcome = .cancelled
            } catch let error as SourceError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.cannotStart(error.localizedDescription))
            }
            self?.finish(id, token: token, outcome: Task.isCancelled ? .cancelled : outcome)
        }
        runs[id] = (token, task)
    }

    private func cancelRun(_ id: String) {
        guard let run = runs.removeValue(forKey: id) else { return }
        run.task.cancel()
        schedule.cancel(id)
        if states[id]?.isRunning == true { states[id]?.isRunning = false }
    }

    private func finish(_ id: String, token: UUID, outcome: Outcome) {
        guard runs[id]?.token == token else { return }
        runs[id] = nil
        schedule.finish(id)
        guard let entry = entries[id] else { return }
        var state = self.state(id)
        state.isRunning = false
        switch outcome {
        case .cancelled:
            break
        case let .result(.output(output)):
            state.output = output
            state.error = nil
            state.lastSuccess = now()
            record(output, id: id, view: entry.source.view)
        case let .result(.needsApproval(approval)):
            schedule.pause(id, for: approval)
            Self.log.info("widget \(id, privacy: .public) waits for approval")
        case let .failure(error):
            state.error = error
            Self.log.error("widget \(id, privacy: .public): \(error.title, privacy: .public): \(error.details, privacy: .public)")
        }
        if states[id] != state { states[id] = state }
    }

    private func record(_ output: SourceOutput, id: String, view: WidgetView) {
        guard view.kind == "sparkline", let value = try? ValueExtraction.number(from: output, view: view) else { return }
        var history = histories[id] ?? SparklineHistory()
        history.append(value, at: now())
        histories[id] = history
        let saved = history
        let store = historyStore
        let surface = self.surface
        Self.historyQueue.async {
            do {
                try store.save(saved, surface: surface, id: id)
            } catch {
                Self.log.error("saving widget history failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func syncStreams() {
        let wanted = isStarted ? schedule.streams.subtracting(heldStreams) : []
        for id in Array(streams.keys) where !wanted.contains(id) { stopStream(id) }
        for id in wanted.sorted() where streams[id] == nil { startStream(id) }
    }

    private func startStream(_ id: String) {
        guard let entry = entries[id], case .command = entry.source.source else { return }
        let request = request(id, entry)
        let built: (command: CommandSource, invocation: ProcessInvocation, remote: Bool)
        do {
            if let blocked = try SourceApprovalGate.blocked(request) {
                schedule.pause(id, for: blocked)
                return
            }
            built = try CommandSourceRunner.invocation(request, environment: runners.environment)
        } catch {
            schedule.begin(id, at: now())
            streamEnded(id, error as? SourceError ?? .cannotStart(error.localizedDescription))
            return
        }
        let session = StreamSession(launcher: runners.launcher, keep: built.command.keep)
        session.onLines = { [weak self, weak session] lines in
            guard let self, let session, self.streams[id] === session else { return }
            var state = self.state(id)
            state.lines = lines
            self.states[id] = state
        }
        session.onEnd = { [weak self, weak session] error in
            guard let self, let session, self.streams[id] === session else { return }
            self.streamEnded(id, error)
        }
        streams[id] = session
        schedule.begin(id, at: now())
        var state = self.state(id)
        state.isRunning = true
        state.ended = false
        state.error = nil
        states[id] = state
        session.start(built.invocation, remote: built.remote)
    }

    private func stopStream(_ id: String) {
        guard let session = streams.removeValue(forKey: id) else { return }
        session.stop()
        schedule.finish(id)
        if states[id]?.isRunning == true { states[id]?.isRunning = false }
    }

    /// A stream that ended on its own waits for ▶ instead of restarting on
    /// the next tick, which would spin a command that exits at once.
    private func streamEnded(_ id: String, _ error: SourceError?) {
        streams[id] = nil
        schedule.finish(id)
        heldStreams.insert(id)
        var state = self.state(id)
        state.isRunning = false
        state.ended = true
        state.error = error
        states[id] = state
        if let error {
            Self.log.error("widget stream \(id, privacy: .public) ended: \(error.details, privacy: .public)")
        }
    }
}
