import Foundation
import DevmachineCore

/// Runs the Add machine wizard's commands, one at a time. A CLI that takes
/// every answer as a flag (`MachineUnattendedAdd`) runs them in the
/// background, the password on stdin, the output shown as it comes. An older
/// one runs them in a terminal pane on this Mac, where `machines add` and
/// `setup` ask their own questions: each step is a small `sh` script that
/// prints a marker when it ends (`TerminalStepMarker`), and the runner
/// watches the pane's scrollback for it. A step that ends without one (an
/// interrupted CLI, a closed pane) is noticed by its shell coming back to
/// the prompt, and nothing waits longer than `stepTimeout`. Stop ends either
/// kind of run.
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
        /// True once the pane's shell is back in the foreground, false while
        /// a program runs in it, nil when that cannot be read.
        var isAtPrompt: (TerminalKind) async -> Bool?
        /// Runs `devmachine <arguments>` with no terminal, `input` on stdin,
        /// each line of output as it comes; answers the exit status.
        var runProcess: ([String], Data?, @escaping @Sendable (String) -> Void) async throws -> Int32
        var beginTask: (String, Int) -> UUID?
        var setTask: (UUID, Int) -> Void
        var endTask: (UUID, Bool) -> Void
        /// The plan's Lima step (`LimaInstaller`). A test that does not set
        /// it gets a refusal, never a download.
        var installLima: (LimaInstall.Method, @escaping @Sendable (String) -> Void) async throws -> Void = { _, _ in
            throw LimaInstallError(message: "Installing Lima is not available here.")
        }
        /// The CLI's own installer, a shell line run with no terminal.
        var installCLI: (@escaping @Sendable (String) -> Void) async throws -> Int32 = { _ in
            throw LimaInstallError(message: "Installing the CLI is not available here.")
        }
    }

    @Published private(set) var statuses: [String: StepStatus] = [:]
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var problem: String?
    /// What a background run printed, every step's command first.
    @Published private(set) var lines: [String] = []
    /// The run went through `runProcess`, not the terminal.
    @Published private(set) var inBackground = false
    /// The failed step's exit status, nil for a stop or an error before it ran.
    @Published private(set) var exitCode: Int32?

    nonisolated static let stopped = "Stopped before it finished. Try again runs this step again."
    nonisolated static let endedWithoutMarker = "The step ended without finishing: the terminal is back at its "
        + "prompt (it was interrupted, or the CLI stopped). Try again runs it again."
    nonisolated static let timedOut = "The step gave no result for too long. If it still runs in the terminal, "
        + "stop it there, then Try again."
    nonisolated static let demoRefusal = "Demo mode never adds a machine."

    let terminalKind: TerminalKind
    private let hooks: Hooks
    private let pollInterval: UInt64
    private let readyTimeout: Int
    private let stepTimeout: TimeInterval
    private var runToken = UUID()
    private var activeStep: MachinePlanStep?
    private var processTask: Task<Int32, Error>?

    /// The shell is asked whether it is back at its prompt only after a few
    /// polls (the step's `sh` needs a moment to take the foreground), then
    /// every few polls, and it has to say so twice in a row.
    private static let promptGracePolls = 6
    private static let promptCheckEvery = 4

    init(
        path: String = NSHomeDirectory(),
        hooks: Hooks? = nil,
        pollInterval: UInt64 = 500_000_000,
        readyTimeout: Int = 40,
        stepTimeout: TimeInterval = 3 * 60 * 60
    ) {
        self.terminalKind = .local(session: Self.sessionName, path: path)
        self.hooks = hooks ?? .live
        self.pollInterval = pollInterval
        self.readyTimeout = readyTimeout
        self.stepTimeout = stepTimeout
    }

    func status(of step: MachinePlanStep) -> StepStatus {
        statuses[step.id] ?? .waiting
    }

    /// Runs every step not done yet, in order, and stops at the first that
    /// fails. A retry calls this again: the steps already done are skipped.
    /// `password` goes to the stdin of the step that reads it, nowhere else.
    /// `limaMethod` is how a missing Lima is installed when the plan has that step.
    func run(
        _ steps: [MachinePlanStep], inTerminal: Bool = true, password: SecretText = SecretText(),
        limaMethod: LimaInstall.Method = .release, label: String = "Adding a machine…",
        demoRefusal: String = MachineStepRunner.demoRefusal
    ) async {
        guard !DemoMode.isActive else {
            reset()
            fail(steps.first, demoRefusal)
            return
        }
        let token = UUID()
        runToken = token
        problem = nil
        exitCode = nil
        phase = .running
        inBackground = !inTerminal
        let task = hooks.beginTask(label, steps.count)
        defer { if let task { hooks.endTask(task, phase == .succeeded) } }

        guard inTerminal else {
            for (index, step) in steps.enumerated() where status(of: step) != .done {
                guard runToken == token else { return }
                if let task { hooks.setTask(task, index) }
                guard await runInBackground(step, password: password, limaMethod: limaMethod, token: token)
                else { return }
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

    /// Ends the step that runs and every step after it: Ctrl-C in the
    /// terminal, or the background process is ended.
    func stop() {
        guard phase == .running else { return }
        runToken = UUID()
        processTask?.cancel()
        processTask = nil
        if !inBackground { hooks.type("\u{03}", terminalKind) }
        fail(activeStep, Self.stopped)
    }

    /// Forgets every step: a new run starts from the first one.
    func reset() {
        runToken = UUID()
        processTask?.cancel()
        processTask = nil
        activeStep = nil
        statuses = [:]
        phase = .idle
        problem = nil
        lines = []
        inBackground = false
        exitCode = nil
    }

    private func runInBackground(
        _ step: MachinePlanStep, password: SecretText, limaMethod: LimaInstall.Method, token: UUID
    ) async -> Bool {
        activeStep = step
        statuses[step.id] = .running
        let before = lines + [(step.isCommand ? "$ " : "▸ ") + step.displayLine]
        lines = before
        let sink = ProcessOutputSink { [weak self] output in
            guard let self, self.runToken == token, self.lines.count < before.count + output.count else { return }
            self.lines = before + output
        }
        let input = step.input == .password ? Data(password.value.utf8) : nil
        let runProcess = hooks.runProcess
        let installLima = hooks.installLima
        let installCLI = hooks.installCLI
        let arguments = step.arguments
        let kind = step.kind
        let work = Task { () async throws -> Int32 in
            switch kind {
            case .installLima:
                try await installLima(limaMethod, sink.receive)
                return 0
            case .installCLI:
                return try await installCLI(sink.receive)
            default:
                return try await runProcess(arguments, input, sink.receive)
            }
        }
        processTask = work
        let status: Int32
        do {
            status = try await work.value
        } catch {
            guard runToken == token else { return false }
            lines = before + sink.snapshot
            fail(step, error.localizedDescription)
            return false
        }
        guard runToken == token else { return false }
        lines = before + sink.snapshot
        guard status == 0 else {
            exitCode = status
            fail(step, MachinePrepare.failureCause(sink.snapshot)
                ?? "\(step.displayLine) ended with an error. The output shows what it said.")
            return false
        }
        statuses[step.id] = .done
        return true
    }

    private func runOne(_ step: MachinePlanStep, executable: String, token: UUID) async -> Bool {
        activeStep = step
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
        let maxPolls = Int(stepTimeout * 1_000_000_000 / Double(max(pollInterval, 1)))
        var polls = 0
        var promptSeen = 0
        while runToken == token {
            if let outcome = outcome(nonce) {
                if outcome {
                    statuses[step.id] = .done
                    return true
                }
                fail(step, "\(step.displayLine) ended with an error. The terminal shows what it said.")
                return false
            }
            if polls >= Self.promptGracePolls, polls % Self.promptCheckEvery == 0 {
                let atPrompt = await hooks.isAtPrompt(terminalKind)
                guard runToken == token else { return false }
                promptSeen = atPrompt == true ? promptSeen + 1 : 0
                if promptSeen >= 2, outcome(nonce) == nil {
                    fail(step, Self.endedWithoutMarker)
                    return false
                }
            }
            if polls >= maxPolls {
                fail(step, Self.timedOut)
                return false
            }
            polls += 1
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        return false
    }

    private func outcome(_ nonce: String) -> Bool? {
        TerminalStepMarker.outcome(
            okSeen: hooks.matchCount(TerminalStepMarker.ok(nonce: nonce), terminalKind) > 0,
            failSeen: hooks.matchCount(TerminalStepMarker.fail(nonce: nonce), terminalKind) > 0)
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
        isAtPrompt: { await TerminalRegistry.shared.isAtPrompt($0) },
        runProcess: { arguments, input, output in
            guard !DemoMode.isActive else {
                throw DevmachineCLIError.commandFailed("Demo mode never adds a machine.")
            }
            let cli = try DevmachineCLI.resolve()
            return try await StreamingProcess.run(
                executable: cli.executable, arguments: arguments,
                environment: LimaInstall.environment(
                    base: CLISelfUpdate.environment(base: cli.environment()), home: NSHomeDirectory()),
                input: input, output: output)
        },
        beginTask: { label, total in AppModel.shared?.beginTask(label: label, total: total) },
        setTask: { id, completed in AppModel.shared?.setTask(id, completed: completed) },
        endTask: { id, succeeded in
            if succeeded { AppModel.shared?.finishTask(id) } else { AppModel.shared?.dropTask(id) }
        },
        installLima: { method, output in
            guard !DemoMode.isActive else { throw LimaInstallError(message: "Demo mode never installs Lima.") }
            try await LimaInstaller.live.install(method, output: output)
        },
        installCLI: { output in
            guard !DemoMode.isActive else { throw LimaInstallError(message: "Demo mode never installs the CLI.") }
            return try await StreamingProcess.run(
                executable: "/bin/zsh", arguments: ["-l", "-c", "setopt pipefail; " + CLIInstallPlan.noHomebrewCommand],
                environment: CLISelfUpdate.environment(base: ProcessInfo.processInfo.environment), output: output)
        })
    }
}
