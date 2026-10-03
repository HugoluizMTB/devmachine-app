import Foundation

/// One CLI command the wizard runs, in order.
public struct MachinePlanStep: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// Not a `devmachine` command: the app installs Lima itself
        /// (`LimaInstall`) before `create-local` needs it.
        case installLima
        /// The CLI's own installer, a shell line, before any `devmachine`.
        case installCLI
        case skills
        case createLocal
        case addMachine
        case addPackage(String)
        case newWorkspace
        case sync
    }

    public let kind: Kind
    public let title: String
    /// Everything after `devmachine`.
    public let arguments: [String]
    /// The CLI asks its own questions in the terminal (a password, a
    /// fingerprint to confirm): the person answers there.
    public let asksInTerminal: Bool
    /// What the step reads on stdin. Only its kind lives here: the value is
    /// handed over by whoever runs it, so it is never in `arguments` or `id`.
    public let input: Input?

    public enum Input: Equatable, Sendable {
        case password
    }

    public init(kind: Kind, title: String, arguments: [String], asksInTerminal: Bool, input: Input? = nil) {
        self.kind = kind
        self.title = title
        self.arguments = arguments
        self.asksInTerminal = asksInTerminal
        self.input = input
    }

    public static let installLimaID = "install-lima"
    public static let installCLIID = "install-cli"

    public var id: String {
        switch kind {
        case .installLima: return Self.installLimaID
        case .installCLI: return Self.installCLIID
        default: return arguments.joined(separator: " ")
        }
    }

    /// Whether the step is a `devmachine` command to show as one.
    public var isCommand: Bool { kind != .installLima && kind != .installCLI }

    /// A failed skills install is a warning: the machine is set up without it.
    public var blocksSetup: Bool { kind != .skills }

    public var displayLine: String {
        switch kind {
        case .installLima: return "Install Lima from \(LimaInstall.releasePage) into ~/.local, checking its SHA-256"
        case .installCLI: return CLIInstallPlan.noHomebrewCommand
        default: return (["devmachine"] + arguments.map(FileUpload.shellQuoted)).joined(separator: " ")
        }
    }

    public static let installCLI = MachinePlanStep(
        kind: .installCLI, title: "Install the devmachine CLI", arguments: [], asksInTerminal: false)
}

/// The commands that turn a wizard's answers into a machine. Nothing here
/// reimplements the CLI: every step is a `devmachine` command, and anything
/// left at the CLI's default adds no flag.
public enum MachinePlan {
    /// Where `create-local` puts a machine, and the root password it ships
    /// with on purpose (the CLI's `local.Address` and `local.Password`).
    public static let localAddress = "127.0.0.1"
    public static let localPassword = "devmachine"

    public struct Answer: Equatable, Sendable {
        public let question: String
        public let answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    /// `unattended` is a CLI that takes every answer as a flag
    /// (`MachineUnattendedAdd`): nothing then asks in a terminal.
    /// `installsLima` puts Lima's own install first, for a local machine
    /// on a Mac without it; only a run in the background can do that.
    public static func steps(
        for draft: MachineDraft, unattended: Bool = false, installsLima: Bool = false
    ) -> [MachinePlanStep] {
        let name = draft.trimmedName
        var steps: [MachinePlanStep] = []
        if unattended, installsLima, draft.kind == .localVM {
            steps.append(MachinePlanStep(
                kind: .installLima, title: "Install Lima", arguments: [], asksInTerminal: false))
        }
        if unattended {
            steps.append(draft.kind == .localVM ? createLocalAndAddStep(for: draft) : unattendedAddStep(for: draft))
        } else {
            if draft.kind == .localVM {
                steps.append(MachinePlanStep(
                    kind: .createLocal, title: "Create \(name) on this Mac",
                    arguments: ["machines", "create-local", name], asksInTerminal: false))
            }
            steps.append(addStep(for: draft))
        }
        for package in draft.packages {
            steps.append(MachinePlanStep(
                kind: .addPackage(package), title: "Add \(package)",
                arguments: ["packages", "add", package, "--machine", name, "--yes"], asksInTerminal: false))
        }
        if !draft.trimmedWorkspace.isEmpty {
            steps.append(MachinePlanStep(
                kind: .newWorkspace, title: "Add the workspace \(draft.trimmedWorkspace)",
                arguments: ["workspaces", "new", draft.trimmedWorkspace, "--machine", name, "--yes"],
                asksInTerminal: false))
        }
        if draft.sync {
            steps.append(MachinePlanStep(
                kind: .sync, title: "Install everything on \(name)",
                arguments: ["sync", "--machine", name, "--yes"], asksInTerminal: false))
        }
        let agents = SkillAgent.ordered(draft.skillAgents)
        if !agents.isEmpty {
            steps.append(MachinePlanStep(
                kind: .skills, title: "Teach " + SkillAgent.names(agents).joined(separator: ", ") + " devmachine",
                arguments: ["skills", "add"] + agents.flatMap { ["--agent", $0] } + ["--yes"],
                asksInTerminal: false))
        }
        return steps
    }

    /// `--address` makes `add` ask nothing, which also means it cannot ask
    /// for a password: a server that takes only one, and every local
    /// machine, goes through the CLI's own questions instead. So does the
    /// first machine of all, which only `setup` can write.
    public static func asksInTerminal(_ draft: MachineDraft, unattended: Bool = false) -> Bool {
        guard !unattended else { return false }
        return !draft.hasConfiguration || draft.kind == .localVM || draft.login == .password
            || draft.expectedFingerprint == nil
    }

    /// `create-local --add` makes the VM and adds it with its public
    /// password, trusting the key it presents on this Mac's loopback.
    private static func createLocalAndAddStep(for draft: MachineDraft) -> MachinePlanStep {
        let essentials = draft.essentials ? [] : ["--no-essentials"]
        return MachinePlanStep(
            kind: .createLocal, title: "Create \(draft.trimmedName) on this Mac and connect it",
            arguments: ["machines", "create-local", draft.trimmedName, "--add"] + (draft.localSize?.arguments ?? [])
                + essentials,
            asksInTerminal: false)
    }

    /// Every answer as a flag. The password is read from stdin; the domain
    /// only goes with the first machine, the one that writes `config.yml`.
    private static func unattendedAddStep(for draft: MachineDraft) -> MachinePlanStep {
        var arguments = ["machines", "add", "--name", draft.trimmedName, "--address", draft.trimmedAddress,
                         "--fingerprint", draft.fingerprintToTrust ?? ""]
        if draft.trimmedUser != MachineDraft.defaultUser { arguments += ["--user", draft.trimmedUser] }
        if draft.trimmedPort != MachineDraft.defaultPort { arguments += ["--port", draft.trimmedPort] }
        var input: MachinePlanStep.Input?
        switch draft.login {
        case .key where draft.keySource == .agent:
            arguments += ["--key", "agent:\(draft.agentKey)"]
        case .key:
            if !draft.trimmedKeyFile.isEmpty { arguments += ["--key", draft.trimmedKeyFile] }
        case .password:
            arguments.append("--password-stdin")
            input = .password
        }
        if !draft.hasConfiguration, !draft.trimmedDomain.isEmpty { arguments += ["--domain", draft.trimmedDomain] }
        if !draft.essentials { arguments.append("--no-essentials") }
        return MachinePlanStep(
            kind: .addMachine, title: "Connect \(draft.trimmedName)", arguments: arguments + ["--yes"],
            asksInTerminal: false, input: input)
    }

    private static func addStep(for draft: MachineDraft) -> MachinePlanStep {
        let title = "Connect \(draft.trimmedName)"
        let essentials = draft.essentials ? [] : ["--no-essentials"]
        guard !asksInTerminal(draft), let fingerprint = draft.expectedFingerprint else {
            let command = draft.hasConfiguration ? ["machines", "add"] : ["setup"]
            return MachinePlanStep(
                kind: .addMachine, title: title, arguments: command + essentials + ["--yes"], asksInTerminal: true)
        }
        var arguments = ["machines", "add", "--name", draft.trimmedName, "--address", draft.address,
                         "--fingerprint", fingerprint]
        if draft.trimmedUser != MachineDraft.defaultUser { arguments += ["--user", draft.trimmedUser] }
        if draft.trimmedPort != MachineDraft.defaultPort { arguments += ["--port", draft.trimmedPort] }
        if !draft.trimmedKeyFile.isEmpty { arguments += ["--key", draft.trimmedKeyFile] }
        return MachinePlanStep(
            kind: .addMachine, title: title, arguments: arguments + essentials + ["--yes"], asksInTerminal: false)
    }

    /// What to type when `machines add` or `setup` asks, in the order they
    /// ask. Empty when nothing is asked.
    public static func terminalAnswers(for draft: MachineDraft, unattended: Bool = false) -> [Answer] {
        guard asksInTerminal(draft, unattended: unattended) else { return [] }
        let local = draft.kind == .localVM
        var answers = [
            Answer(question: "machine name", answer: draft.trimmedName),
            Answer(question: "address", answer: local ? localAddress : draft.address),
            Answer(question: "administrative login", answer: local ? MachineDraft.defaultUser : draft.trimmedUser),
            Answer(question: "SSH port", answer: local ? "the port create-local printed above" : draft.trimmedPort),
        ]
        if !draft.hasConfiguration {
            answers.append(Answer(question: "domain", answer: "your domain, or leave it empty"))
        }
        let fingerprint: String
        if local {
            fingerprint = "yes: this machine runs on this Mac"
        } else if let expected = draft.expectedFingerprint {
            fingerprint = "yes, only if it shows \(expected)"
        } else {
            fingerprint = "yes, only if it matches your provider's console"
        }
        answers.append(Answer(question: "trust the fingerprint", answer: fingerprint))
        answers.append(Answer(
            question: "how to log in",
            answer: draft.trimmedKeyFile.isEmpty || local
                ? "1, a key devmachine makes" : "2, then \(draft.trimmedKeyFile)"))
        let password: String
        if local {
            password = localPassword
        } else if draft.login == .password {
            password = "the server's password, from your provider"
        } else {
            password = "not asked when the key already logs in"
        }
        answers.append(Answer(question: "password", answer: password))
        return answers
    }
}

/// How a step run in a terminal reports its exit status: a small `sh`
/// script runs the command and prints a marker when it ends, and the runner
/// looks for that marker in the pane's scrollback. Only `sh <script>` is
/// typed, so the line works in any login shell (fish quotes differently),
/// the command keeps the terminal for its questions, and the echoed line
/// never holds the marker.
public enum TerminalStepMarker {
    public static func ok(nonce: String) -> String { "__DM_\(nonce)_OK__" }
    public static func fail(nonce: String) -> String { "__DM_\(nonce)_FAIL__" }

    /// Shows the command as the review showed it, runs it, then prints the
    /// marker, put together by `printf` so the file never holds it either.
    public static func script(executable: String, step: MachinePlanStep, nonce: String) -> String {
        let command = ([executable] + step.arguments).map(FileUpload.shellQuoted).joined(separator: " ")
        return [
            "printf '%s\\n' " + FileUpload.singleQuoted("$ " + step.displayLine),
            command,
            "if [ $? -eq 0 ]; then r=OK; else r=FAIL; fi",
            "printf '__DM_%s_%s__\\n' \(nonce) \"$r\"",
        ].joined(separator: "\n") + "\n"
    }

    public static func typedLine(scriptPath: String) -> String {
        "sh " + FileUpload.shellQuoted(scriptPath)
    }

    public static func newNonce() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10)).lowercased()
    }

    /// True when the step succeeded, false when it failed, nil while it runs.
    public static func outcome(okSeen: Bool, failSeen: Bool) -> Bool? {
        if okSeen { return true }
        if failSeen { return false }
        return nil
    }
}
