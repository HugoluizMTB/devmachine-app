import Foundation
import DevmachineCore

/// Runs the Add machine wizard's commands, one at a time. A CLI that takes
/// every answer as a flag (`MachineUnattendedAdd`) runs them in the
/// background, the password on stdin, the output shown as it comes. An older
/// one runs them in a terminal pane on this Mac, where `machines add` and
/// `setup` ask their own questions: each step is a small `sh` script that
/// prints a marker when it ends (`TerminalStepMarker`), and the runner
/// watches the pane's scrollback for it.
@MainActor
final class MachineStepRunner: ObservableObject {
    nonisolated static let sessionName = "devmachine-add-machine"

    enum StepStatus: Equatable {
        case waiting, running, done, failed
    }

    enum Phase: Equatable {
        case idle
        case running
        case succeeded
        case failed(step: String)
    }

    @MainActor
    struct Hooks {
        var executable: () -> String?
        var isReady: (TerminalKind) -> Bool
        var type: (String, TerminalKind) -> Void
        var matchCount: (String, TerminalKind) -> Int
        var writeScript: (String, String) throws -> String
        /// Runs `devmachine <arguments>` with no terminal, `input` on stdin,
        /// each line of output as it comes; answers the exit status.
        var runProcess: ([String], Data?, @escaping @Sendable (String) -> Void) async throws -> Int32
        var beginTask: (String, Int) -> UUID?
        var setTask: (UUID, Int) -> Void
        var endTask: (UUID, Bool) -> Void
    }

    @Published private(set) var statuses: [String: StepStatus] = [:]
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var problem: String?
    /// What a background run printed, every step's command first.
    @Published private(set) var lines: [String] = []
    /// The run went through `runProcess`, not the terminal.
    @Published private(set) var inBackground = false

    let terminalKind: TerminalKind
    private let hooks: Hooks
    private let pollInterval: UInt64
    private let readyTimeout: Int
    private var runToken = UUID()

    init(
        path: String = NSHomeDirectory(),
        hooks: Hooks? = nil,
        pollInterval: UInt64 = 500_000_000,
        readyTimeout: Int = 40
    ) {
        self.terminalKind = .local(session: Self.sessionName, path: path)
        self.hooks = hooks ?? .live
        self.pollInterval = pollInterval
        self.readyTimeout = readyTimeout
    }

    func status(of step: MachinePlanStep) -> StepStatus {
        statuses[step.id] ?? .waiting
    }

    /// Runs every step not done yet, in order, and stops at the first that
    /// fails. A retry calls this again: the steps already done are skipped.
    /// `password` goes to the stdin of the step that reads it, nowhere else.
    func run(_ steps: [MachinePlanStep], inTerminal: Bool = true, password: SecretText = SecretText()) async {
        let token = UUID()
        runToken = token
        problem = nil
        phase = .running
        inBackground = !inTerminal
        let task = hooks.beginTask("Adding a machine…", steps.count)
        defer { if let task { hooks.endTask(task, phase == .succeeded) } }

        guard inTerminal else {
            for (index, step) in steps.enumerated() where status(of: step) != .done {
                guard runToken == token else { return }
                if let task { hooks.setTask(task, index) }
                guard await runInBackground(step, password: password, token: token) else { return }
            }
            phase = .succeeded
            return
        }
        guard let executable = hooks.executable() else {
            fail(steps.first { status(of: $0) != .done }, "The devmachine CLI was not found on this Mac.")
            return
        }
        guard await waitForTerminal(token) else {
            fail(steps.first { status(of: $0) != .done }, "The terminal below did not start.")
            return
        }
        for (index, step) in steps.enumerated() where status(of: step) != .done {
            guard runToken == token else { return }
            if let task { hooks.setTask(task, index) }
            guard await runOne(step, executable: executable, token: token) else { return }
        }
        phase = .succeeded
    }

    /// Forgets every step: a new run starts from the first one.
    func reset() {
        runToken = UUID()
        statuses = [:]
        phase = .idle
        problem = nil
        lines = []
        inBackground = false
    }

    private func runInBackground(_ step: MachinePlanStep, password: SecretText, token: UUID) async -> Bool {
        statuses[step.id] = .running
        let before = lines + ["$ " + step.displayLine]
        lines = before
        let sink = ProcessOutputSink { [weak self] output in
            guard let self, self.runToken == token, self.lines.count < before.count + output.count else { return }
            self.lines = before + output
        }
        let input = step.input == .password ? Data(password.value.utf8) : nil
        let status: Int32
        do {
            status = try await hooks.runProcess(step.arguments, input, sink.receive)
        } catch {
            guard runToken == token else { return false }
            lines = before + sink.snapshot
            fail(step, error.localizedDescription)
            return false
        }
        guard runToken == token else { return false }
        lines = before + sink.snapshot
        guard status == 0 else {
            fail(step, MachinePrepare.failureCause(sink.snapshot)
                ?? "\(step.displayLine) ended with an error. The output shows what it said.")
            return false
        }
        statuses[step.id] = .done
        return true
    }

    private func runOne(_ step: MachinePlanStep, executable: String, token: UUID) async -> Bool {
        statuses[step.id] = .running
        let nonce = TerminalStepMarker.newNonce()
        let script = TerminalStepMarker.script(executable: executable, step: step, nonce: nonce)
        do {
            let path = try hooks.writeScript(script, nonce)
            hooks.type(TerminalStepMarker.typedLine(scriptPath: path) + "\r", terminalKind)
        } catch {
            fail(step, "Could not write the step's script: \(error.localizedDescription)")
            return false
        }
        while runToken == token {
            if let outcome = TerminalStepMarker.outcome(
                okSeen: hooks.matchCount(TerminalStepMarker.ok(nonce: nonce), terminalKind) > 0,
                failSeen: hooks.matchCount(TerminalStepMarker.fail(nonce: nonce), terminalKind) > 0) {
                if outcome {
                    statuses[step.id] = .done
                    return true
                }
                fail(step, "\(step.displayLine) ended with an error. The terminal shows what it said.")
                return false
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        return false
    }

    private func waitForTerminal(_ token: UUID) async -> Bool {
        for _ in 0..<readyTimeout {
            guard runToken == token else { return false }
            if hooks.isReady(terminalKind) { return true }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        return hooks.isReady(terminalKind)
    }

    private func fail(_ step: MachinePlanStep?, _ message: String) {
        if let step { statuses[step.id] = .failed }
        problem = message
        phase = .failed(step: step?.id ?? "")
    }

    #if DEBUG
    /// Demo walks only: a run in any state, without a terminal.
    func seedDemo(
        statuses: [String: StepStatus], phase: Phase, problem: String? = nil, lines: [String]? = nil
    ) {
        self.statuses = statuses
        self.phase = phase
        self.problem = problem
        self.lines = lines ?? []
        inBackground = lines != nil
    }
    #endif
}

extension MachineStepRunner.Hooks {
    /// The scripts live in the app's own temporary folder, readable only by
    /// this account, and hold nothing but the commands the review showed.
    @MainActor static var live: MachineStepRunner.Hooks { MachineStepRunner.Hooks(
        executable: { (try? DevmachineCLI.resolve())?.executable },
        isReady: { TerminalRegistry.shared.isStarted($0) },
        type: { TerminalRegistry.shared.type($0, into: $1) },
        matchCount: { TerminalRegistry.shared.matchCount($0, in: $1) },
        writeScript: { script, nonce in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devmachine-steps")
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = directory.appendingPathComponent("\(nonce).sh")
            try script.write(to: file, atomically: true, encoding: .utf8)
            return file.path
        },
        runProcess: { arguments, input, output in
            guard !DemoMode.isActive else {
                throw DevmachineCLIError.commandFailed("Demo mode never adds a machine.")
            }
            let cli = try DevmachineCLI.resolve()
            return try await StreamingProcess.run(
                executable: cli.executable, arguments: arguments,
                environment: CLISelfUpdate.environment(base: cli.environment()), input: input, output: output)
        },
        beginTask: { label, total in AppModel.shared?.beginTask(label: label, total: total) },
        setTask: { id, completed in AppModel.shared?.setTask(id, completed: completed) },
        endTask: { id, succeeded in
            if succeeded { AppModel.shared?.finishTask(id) } else { AppModel.shared?.dropTask(id) }
        })
    }
}
