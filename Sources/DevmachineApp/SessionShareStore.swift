import Foundation
import DevmachineCore

protocol SessionShareRunning: Sendable {
    func run(_ arguments: [String]) async throws -> CLIOutput
}

/// Runs `devmachine run --package session-share` off the main thread, with
/// the same ssh agent the rest of the app hands the CLI.
struct ProcessSessionShareRunner: SessionShareRunning {
    var cli: @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() }

    func run(_ arguments: [String]) async throws -> CLIOutput {
        let cli = self.cli
        return try await Task.detached {
            let instance = try cli()
            let result = try instance.runner.runCapturing(
                executable: instance.executable, args: arguments, environment: instance.environment())
            return CLIOutput(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
        }.value
    }
}

/// A session the person asked to share, waiting in the Share sheet.
struct SessionShareRequest: Identifiable, Equatable {
    let alias: String
    let workspace: String
    let session: String
    var id: String { "\(alias)/\(session)" }
}

/// What the result sheet shows once a call answered: the link and the
/// password, or why it failed. Each answer has its own id, so a second
/// failure with the same title still replaces the first on screen.
struct SessionShareOutcome: Identifiable, Equatable {
    enum Result: Equatable {
        /// `unpublished` says why the link only opens on the machine.
        case started(SessionShareRecord, password: String?, unpublished: DMErrorState?)
        case failed(DMErrorState)
    }

    let id = UUID()
    let result: Result

    static func started(_ record: SessionShareRecord, password: String?, unpublished: DMErrorState? = nil) -> Self {
        Self(result: .started(record, password: password, unpublished: unpublished))
    }

    static func failed(_ state: DMErrorState) -> Self {
        Self(result: .failed(state))
    }
}

/// The shares this Mac started: who is shared, until when, and the history
/// Settings lists. Everything that writes (start, stop, extend) runs only
/// from a button the person pressed; the poll only reads.
@MainActor
final class SessionShareStore: ObservableObject {
    static let shared = NSClassFromString("XCTestCase") == nil && !DemoMode.isActive
        ? SessionShareStore(
            runner: ProcessSessionShareRunner(), history: SessionShareHistory(fileURL: SessionShareHistory.defaultFileURL),
            polls: true)
        : SessionShareStore(
            runner: ProcessSessionShareRunner(cli: {
                throw DevmachineCLIError.commandFailed("no CLI under tests or in demo mode")
            }),
            history: SessionShareHistory(fileURL: nil))

    @Published private(set) var records: [SessionShareRecord] {
        didSet { if records != oldValue { onChange?(liveRecords) } }
    }
    /// Called with the live shares whenever the list changes.
    var onChange: (([SessionShareRecord]) -> Void)? {
        didSet { onChange?(liveRecords) }
    }
    @Published var outcome: SessionShareOutcome?
    @Published private(set) var busy: Set<String> = []

    private let runner: any SessionShareRunning
    private let history: SessionShareHistory
    private let now: () -> Date
    private var pollTask: Task<Void, Never>?
    var pollInterval: UInt64 = 30_000_000_000
    var isPaused: (String) -> Bool = { AppModel.shared?.isPollingPaused(alias: $0) ?? false }

    /// Only the app's own store polls; a test drives `refresh` itself.
    private let polls: Bool

    init(
        runner: any SessionShareRunning, history: SessionShareHistory, polls: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.runner = runner
        self.history = history
        self.polls = polls
        self.now = now
        records = history.load()
    }

    #if DEBUG
    func seedDemo(_ shown: [SessionShareRecord]) {
        records = shown
    }
    #endif

    func liveShare(alias: String, session: String) -> SessionShareRecord? {
        let at = now()
        return records.first { $0.alias == alias && $0.session == session && $0.isLive(at: at) }
    }

    var liveRecords: [SessionShareRecord] {
        let at = now()
        return records.filter { $0.isLive(at: at) }
    }

    func start(_ request: SessionShareRequest, name: String, mode: SessionShareMode, duration: SessionShareDuration) async {
        let task = AppModel.shared?.beginTask(label: "Sharing \(request.session)…", total: 1)
        defer { if let task { AppModel.shared?.finishTask(task) } }
        busy.insert(request.id)
        defer { busy.remove(request.id) }
        let arguments = SessionShareCommand.startArguments(
            workspace: request.workspace, session: request.session, mode: mode, duration: duration, name: name)
        do {
            let output = try await runner.run(arguments)
            guard output.exitCode == 0 else {
                outcome = .failed(Self.failure("Couldn't share \(request.session)", output: output, workspace: request.workspace))
                return
            }
            let started = try SessionShareCommand.parseStart(output.stdout)
            var record = SessionShareRecord(started.share, workspace: request.workspace, alias: request.alias)
            var unpublished: DMErrorState?
            if started.share.isLocalOnly, let local = started.share.url {
                switch await publish(workspace: request.workspace, localURL: local) {
                case let .success(base): record.url = SessionShareCommand.link(base: base, id: record.id)
                case let .failure(problem): unpublished = problem.state
                }
            }
            records.removeAll { $0.id == record.id }
            records.insert(record, at: 0)
            persist()
            outcome = .started(record, password: started.password, unpublished: unpublished)
            startPolling()
        } catch {
            outcome = .failed(DMErrorState(title: "Couldn't share \(request.session)", message: Self.describe(error)))
        }
    }

    struct PublishProblem: Error {
        let state: DMErrorState
    }

    /// The share server listens only on the machine. The first share of a
    /// workspace publishes it once, at `share-<workspace>.<domain>` through
    /// `devmachine expose`, or on Tailscale Funnel when no domain is set, and
    /// tells the tool that address so every later link starts with it.
    private func publish(workspace: String, localURL: String) async -> Result<String, PublishProblem> {
        let title = "The link only opens on the machine"
        guard let port = SessionShareCommand.port(of: localURL) else {
            return .failure(PublishProblem(state: DMErrorState(title: title, message: "No port in \(localURL).")))
        }
        let config = try? await runner.run(SessionShareCommand.configArguments)
        guard let domain = config.flatMap({ SessionShareCommand.parseDomain($0.stdout) }) else {
            return await publishOnFunnel(workspace: workspace, title: title)
        }
        let host = SessionShareCommand.publicHost(workspace: workspace, domain: domain)
        let task = AppModel.shared?.beginTask(label: "Publishing \(host)…", total: 1)
        defer { if let task { AppModel.shared?.finishTask(task) } }
        do {
            let added = try await runner.run(SessionShareCommand.exposeAddArguments(workspace: workspace, port: port, host: host))
            let message = added.stderr.isEmpty ? added.stdout : added.stderr
            guard added.exitCode == 0 || message.contains("already") else {
                return .failure(PublishProblem(state: DMErrorState(
                    title: title, cause: "Publishing \(host) failed.", details: message)))
            }
            let base = "https://\(host)"
            let recorded = try await runner.run(SessionShareCommand.proxyArguments(workspace: workspace, url: base))
            guard recorded.exitCode == 0 else {
                return .failure(PublishProblem(state: DMErrorState(
                    title: title, cause: "\(host) is published, but session-share did not take the address.",
                    details: recorded.stderr.isEmpty ? recorded.stdout : recorded.stderr)))
            }
            return .success(base)
        } catch {
            return .failure(PublishProblem(state: DMErrorState(title: title, message: Self.describe(error))))
        }
    }

    private func publishOnFunnel(workspace: String, title: String) async -> Result<String, PublishProblem> {
        let output: CLIOutput
        do {
            output = try await runner.run(SessionShareCommand.funnelArguments(workspace: workspace))
        } catch {
            return .failure(PublishProblem(state: DMErrorState(title: title, message: Self.describe(error))))
        }
        if output.exitCode == 0, let url = (try? SessionShareCommand.parseExposedURL(output.stdout)) ?? nil {
            return .success(url)
        }
        return .failure(PublishProblem(state: DMErrorState(
            title: title,
            cause: "No domain is set in the devmachine configuration, and Tailscale Funnel is not available on this machine. Set a domain in Settings → General, then share again.",
            details: output.stderr.isEmpty ? output.stdout : output.stderr)))
    }

    func stop(_ record: SessionShareRecord) async {
        await change(record, label: "Stopping the share of \(record.session)…", failureTitle: "Couldn't stop sharing \(record.session)",
            arguments: SessionShareCommand.stopArguments(workspace: record.workspace, id: record.id))
    }

    func extend(_ record: SessionShareRecord, by duration: String = "30m") async {
        await change(record, label: "Adding time to \(record.session)…", failureTitle: "Couldn't add time to \(record.session)",
            arguments: SessionShareCommand.extendArguments(workspace: record.workspace, id: record.id, by: duration))
    }

    private func change(_ record: SessionShareRecord, label: String, failureTitle: String, arguments: [String]) async {
        let task = AppModel.shared?.beginTask(label: label, total: 1)
        defer { if let task { AppModel.shared?.finishTask(task) } }
        busy.insert(record.id)
        defer { busy.remove(record.id) }
        do {
            let output = try await runner.run(arguments)
            guard output.exitCode == 0 else {
                outcome = .failed(Self.failure(failureTitle, output: output, workspace: record.workspace))
                return
            }
            let share = try SessionShareCommand.parseShare(output.stdout)
            update(record.id) { $0.update(from: share) }
        } catch {
            outcome = .failed(DMErrorState(title: failureTitle, message: Self.describe(error)))
        }
    }

    /// Reads every workspace that has a live share, one after the other, as
    /// the session sweep does. A paused workspace is left alone.
    func refresh() async {
        let workspaces = Dictionary(liveRecords.map { ($0.workspace, $0.alias) }, uniquingKeysWith: { first, _ in first })
        for (workspace, alias) in workspaces.sorted(by: { $0.key < $1.key }) where !isPaused(alias) {
            guard let output = try? await runner.run(SessionShareCommand.listArguments(workspace: workspace)),
                  output.exitCode == 0,
                  let shares = try? SessionShareCommand.parseList(output.stdout) else { continue }
            let merged = SessionShareHistory.merge(records, with: shares, workspace: workspace, now: now())
            if merged != records {
                records = merged
                persist()
            }
        }
    }

    func startPolling() {
        guard polls, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled, !self.liveRecords.isEmpty {
                await self.refresh()
                // A share can run out by time alone, with nothing in the
                // records changing: the live list is handed over every round.
                self.onChange?(self.liveRecords)
                try? await Task.sleep(nanoseconds: self.pollInterval)
            }
            self?.onChange?(self?.liveRecords ?? [])
            self?.pollTask = nil
        }
    }

    func clearEnded() {
        let at = now()
        records.removeAll { !$0.isLive(at: at) }
        persist()
    }

    private func update(_ id: String, _ change: (inout SessionShareRecord) -> Void) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[i])
        persist()
    }

    private func persist() {
        try? history.save(records)
    }

    static func failure(_ title: String, output: CLIOutput, workspace: String) -> DMErrorState {
        let message = output.stderr.isEmpty ? output.stdout : output.stderr
        if SessionShareCommand.isMissingPackage(message) {
            return DMErrorState(
                title: title,
                cause: "The workspace \(workspace) does not have the session-share package yet. Add it in Settings → Packages, then sync.",
                details: message)
        }
        return DMErrorState(title: title, cause: FailureCause(message: message)?.summary, details: message)
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
