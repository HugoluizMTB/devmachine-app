import Foundation
import DevmachineCore

/// One installed DNS provider, as `dns providers` reports it — the app only
/// needs the name for the tab strip; `dns list` resolves the provider and
/// zone itself.
struct CLIDNSProvider: Decodable, Equatable, Sendable {
    let name: String
    let zones: [String]
    let error: String?
}

private struct CLIDNSProviderList: Decodable {
    let providers: [CLIDNSProvider]
}

private struct CLIDNSListResult: Decodable {
    let zone: String
    let provider: String
    let records: [DNSRecordRow]
}

struct CLIWorkspace: Codable, Equatable, Sendable {
    let name: String
    let machine: String
    let user: String
    let packages: [String]
}

private struct CLIWorkspaceList: Decodable {
    let workspaces: [CLIWorkspace]
}

struct CLIConfigPath: Decodable, Equatable, Sendable {
    let path: String
    let source: String
}

/// One entry of `config show`'s `machines` list. `hosts` is every address the
/// CLI would try in order (tailnet first, then a public fallback) — the app
/// only needs one to show, so it picks the first that is not a tailnet
/// address (`100.64.0.0/10`).
struct CLIConfigMachine: Decodable, Equatable, Sendable {
    let name: String
    let hosts: [String]
    let adminUser: String
    let port: Int
    let workspaces: [String]
    let isSelf: Bool

    enum CodingKeys: String, CodingKey {
        case name, hosts, workspaces, port
        case adminUser = "admin_user"
        case isSelf = "self"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        hosts = try c.decodeIfPresent([String].self, forKey: .hosts) ?? []
        adminUser = try c.decodeIfPresent(String.self, forKey: .adminUser) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 0
        workspaces = try c.decodeIfPresent([String].self, forKey: .workspaces) ?? []
        isSelf = try c.decodeIfPresent(Bool.self, forKey: .isSelf) ?? false
    }
}

struct CLIConfigWorkspace: Decodable, Equatable, Sendable {
    let name: String
    let machine: String
    let user: String
}

struct CLIConfigShow: Decodable, Equatable, Sendable {
    let machines: [CLIConfigMachine]
    let workspaces: [CLIConfigWorkspace]
    let domain: String
}

/// One entry of `devmachine --format json aliases` — the exact ssh host
/// name for a workspace, as the CLI itself wrote it, instead of the app
/// guessing at a `<workspace>-<suffix>` pattern.
struct CLIAlias: Decodable, Equatable, Sendable {
    let name: String
    let host: String
    let user: String
    let port: Int
}

private struct CLIAliasList: Decodable {
    let aliases: [CLIAlias]
}

/// One entry of `packages list`: `installedOn` reads like `"machine devmachine"`
/// or `"workspace acme"`.
struct CLIPackage: Codable, Equatable, Sendable {
    let name: String
    let scope: String
    let installedOn: [String]

    enum CodingKeys: String, CodingKey {
        case name, scope
        case installedOn = "installed_on"
    }

    func isInstalled(onMachine machine: String) -> Bool {
        installedOn.contains("machine \(machine)")
    }
}

private struct CLIPackageList: Decodable {
    let packages: [CLIPackage]
}

struct CLIMachine: Codable, Equatable, Sendable {
    let name: String
    let isSelf: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case isSelf = "self"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        isSelf = try c.decodeIfPresent(Bool.self, forKey: .isSelf) ?? false
    }

    init(name: String, isSelf: Bool) {
        self.name = name
        self.isSelf = isSelf
    }
}

struct ExposureListing: Codable, Equatable, Sendable {
    let sites: [ExposedSite]
    let warning: String?

    /// The CLI's own wording when the machine has no caddy package.
    var caddyIsMissing: Bool { warning?.contains("caddy is not on") ?? false }
}

enum DevmachineCLIError: LocalizedError, Equatable {
    case commandFailed(String)
    case executableNotFound([String])
    case needsNewerCLI(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            return detail.trimmingCharacters(in: .whitespacesAndNewlines)
        case .executableNotFound(let paths):
            return "Devmachine CLI was not found at \(paths.joined(separator: " or ")). Install it with `brew install mydevmachine/tap/devmachine`."
        case .needsNewerCLI(let command):
            return "The installed devmachine CLI has no `\(command)` yet. Update it with `devmachine update`."
        }
    }

    /// A package command the installed release does not know yet — the
    /// machine has an older `devmachine-app` than the app expects. The fix is
    /// `devmachine packages pin` then `sync`, not the "add the package" gate.
    var isUnknownPackageCommand: Bool {
        guard case let .commandFailed(detail) = self else { return false }
        return detail.contains("does not accept")
    }
}

struct DevmachineCLI: Sendable {
    let executable: String
    let runner: any CommandRunner
    let customSocket: String?
    let socketFileExists: @Sendable (String) -> Bool
    let processEnvironment: [String: String]

    init(
        executable: String,
        runner: any CommandRunner = ProcessRunner(),
        customSocket: String? = nil,
        socketFileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executable = executable
        self.runner = runner
        self.customSocket = customSocket
        self.socketFileExists = socketFileExists
        self.processEnvironment = processEnvironment
    }

    static func resolve(
        injected: String? = nil,
        runner: any CommandRunner = ProcessRunner(),
        customSocket: String? = RemoteCommands.SSHAgentSocketPreference.shared.current(),
        exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) throws -> DevmachineCLI {
        let paths = [injected].compactMap { $0 } + [
            "/opt/homebrew/bin/devmachine",
            "/usr/local/bin/devmachine",
        ]
        guard let executable = paths.first(where: exists) else {
            throw DevmachineCLIError.executableNotFound(paths)
        }
        return DevmachineCLI(executable: executable, runner: runner, customSocket: customSocket)
    }

    /// Publishes a workspace's port. The CLI applies the route on Caddy at
    /// once and says how it went in JSON (0.7.21 and newer); the whole output
    /// comes back, because a failed apply still printed what it recorded.
    func exposeAdd(workspace: String, port: Int, host: String) throws -> CLIOutput {
        let result = try runner.runCapturing(
            executable: executable,
            args: [
                "--format", "json", "expose", "add", workspace, String(port),
                "--host", host, "--publish",
            ],
            environment: environment()
        )
        return CLIOutput(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
    }

    /// Saves `paths` from the workspace into `directory` on this Mac. The CLI
    /// answers per path, so one missing file does not hide the others.
    func download(paths: [String], workspace: String, to directory: String) throws -> [DownloadedFile] {
        let result = try runner.runCapturing(
            executable: executable,
            args: FileTransfer.downloadArguments(paths: paths, workspace: workspace, to: directory),
            environment: environment()
        )
        if let files = FileTransfer.parseDownloads(result.stdout) { return files }
        if FileTransfer.isUnknownCommand(result.stderr, FileTransfer.downloadCommand) {
            throw DevmachineCLIError.needsNewerCLI(FileTransfer.downloadCommand)
        }
        try requireSuccess(result)
        throw DevmachineCLIError.commandFailed("The CLI gave no result for the download.")
    }

    /// Sends `files` into `directory` in the workspace's home.
    func upload(files: [String], workspace: String, directory: String) throws -> [UploadedFile] {
        let result = try runner.runCapturing(
            executable: executable,
            args: FileTransfer.uploadArguments(files: files, workspace: workspace, directory: directory),
            environment: environment()
        )
        if let files = FileTransfer.parseUploads(result.stdout) { return files }
        try requireSuccess(result)
        throw DevmachineCLIError.commandFailed("The CLI gave no result for the upload.")
    }

    /// What `machine`'s Caddy publishes. `expose list` acts on one machine
    /// and refuses to guess with several configured, so the machine is
    /// always named. A machine it cannot ask still exits 0: it prints `null`
    /// and says why on stderr, which is kept as `warning`.
    func listExposures(machine: String) throws -> ExposureListing {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--machine", machine, "--format", "json", "expose", "list"],
            environment: environment()
        )
        try requireSuccess(result)
        let sites = try JSONDecoder().decode([ExposedSite]?.self, from: Data(result.stdout.utf8)) ?? []
        let warning = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExposureListing(sites: sites, warning: warning.isEmpty ? nil : warning)
    }

    /// Stops publishing a site, on Caddy at once when the machine answers.
    /// `--yes` skips the CLI's own confirmation prompt: the app already asked.
    func exposeRemove(host: String, machine: String) throws -> CLIOutput {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--machine", machine, "--format", "json", "expose", "rm", host, "--yes"],
            environment: environment()
        )
        return CLIOutput(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
    }

    /// Every DNS provider installed on `machine`, and the zones it can see —
    /// the tab strip only shows a tab for a provider that is here.
    func dnsProviders(machine: String) throws -> [CLIDNSProvider] {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--machine", machine, "--format", "json", "dns", "providers"],
            environment: environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode(CLIDNSProviderList.self, from: Data(result.stdout.utf8)).providers
    }

    /// Every record `provider` holds for `zone` on `machine` — read-only,
    /// straight from the registrar.
    func dnsList(machine: String, provider: String, zone: String) throws -> [DNSRecordRow] {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--machine", machine, "--format", "json", "dns", "list", zone, "--dns-provider", provider],
            environment: environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode(CLIDNSListResult.self, from: Data(result.stdout.utf8)).records
    }

    func listWorkspaces() throws -> [CLIWorkspace] {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "workspaces", "list"],
            environment: environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode(CLIWorkspaceList.self, from: Data(result.stdout.utf8)).workspaces
    }

    func listMachines() throws -> [CLIMachine] {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "machines", "list"],
            environment: environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode([CLIMachine].self, from: Data(result.stdout.utf8))
    }

    /// `machines list`, decoded with every field `config show`'s `machines`
    /// carries (hosts included) — the same JSON shape, so the app can show a
    /// machine's address without a second call to `configShow()`.
    func listConfigMachines() throws -> [CLIConfigMachine] {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "machines", "list"],
            environment: environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode([CLIConfigMachine].self, from: Data(result.stdout.utf8))
    }

    /// Every configured machine that is not this Mac — the set Stats and the
    /// package gate check, instead of only the first one.
    func nonSelfMachines() throws -> [CLIConfigMachine] {
        try listConfigMachines().filter { !$0.isSelf }
    }

    /// Where the CLI keeps its configuration — the folder the app used to ask
    /// the person to type by hand.
    func configPath() throws -> CLIConfigPath {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "config", "path"],
            environment: environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode(CLIConfigPath.self, from: Data(result.stdout.utf8))
    }

    func version() throws -> String {
        let result = try runner.runCapturing(executable: executable, args: ["version"], environment: environment())
        try requireSuccess(result)
        return result.stdout
    }

    /// Every machine and workspace the CLI knows about, plus the base domain
    /// new subdomains are created under.
    func configShow() throws -> CLIConfigShow {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "config", "show"],
            environment: environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode(CLIConfigShow.self, from: Data(result.stdout.utf8))
    }

    /// The exact ssh `Host` entry name for every workspace, as the CLI wrote
    /// it to `~/.ssh/config` — the app no longer has to guess a suffix.
    func aliases() throws -> [CLIAlias] {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "aliases"],
            environment: environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode(CLIAliasList.self, from: Data(result.stdout.utf8)).aliases
    }

    /// Every package the CLI knows about, and which machine or workspace has
    /// it — used to check whether a machine has `devmachine-app` before the
    /// app relies on it for stats or Caddy logs.
    func packages() throws -> [CLIPackage] {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "packages", "list"],
            environment: environment()
        )
        try requireSuccess(result)
        return try JSONDecoder().decode(CLIPackageList.self, from: Data(result.stdout.utf8)).packages
    }

    /// The first configured server, for onboarding's "is a server set up"
    /// check only. `self` is the Mac the app runs on, never the answer. A
    /// command that acts on a server names its machine instead of asking
    /// this: with several, the first one is a guess.
    func resolveAdminMachine() throws -> String {
        let machines = try listMachines()
        guard let machine = machines.first(where: { !$0.isSelf }) else {
            throw DevmachineCLIError.commandFailed(
                "No machine is configured. Run `devmachine machines add` first.")
        }
        return machine.name
    }

    /// Runs a shell command as `machine`'s admin, through the CLI's own
    /// connection (reused for 5 minutes, host key checked, the configured key
    /// or agent, the address fallback including tailscale) — never a raw ssh
    /// alias, which a machine's admin login may have no `~/.ssh/config` entry
    /// for.
    func run(machine: String, command: String) throws -> String {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["run", "--machine", machine, "--", command],
            environment: environment()
        )
        try requireSuccess(result)
        return result.stdout
    }

    /// Runs a command from a package installed on `machine`'s admin account —
    /// `devmachine-app`'s `stats` and `caddy-logs`. Distinct from `run(machine:command:)`,
    /// which runs a plain shell snippet: this goes through the package's own
    /// entrypoint, so the machine needs the package installed (`packages()`
    /// checks that first) and a released version new enough to accept the
    /// command (`DevmachineCLIError.commandFailed` with `isUnknownPackageCommand`).
    func run(machine: String, package: String, args: [String]) throws -> String {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["run", "--machine", machine, "--package", package, "--"] + args,
            environment: environment()
        )
        try requireSuccess(result)
        return result.stdout
    }

    /// `devmachine tunnel`, as a command line to spawn and keep: it holds its
    /// ssh open until it is stopped, so it cannot go through `runner`.
    func tunnelCommand(workspace: String, remotePort: Int, localPort: Int)
        -> (executable: String, args: [String], environment: [String: String]) {
        (executable,
         ["tunnel", workspace, String(remotePort), "--local", String(localPort)],
         environment())
    }

    /// What `doctor` produced: a parsed report, or — when the CLI printed a
    /// text table this app's parser does not recognize — its raw stdout, so
    /// nothing is thrown away just because it could not be parsed.
    enum DoctorOutcome: Equatable, Sendable {
        case report(DoctorReport)
        case raw(String)
    }

    /// `devmachine doctor --machine <machine>`: the health of a configured,
    /// non-self machine.
    func doctor(machine: String) throws -> DoctorOutcome {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "doctor", "--machine", machine],
            environment: environment()
        )
        return try doctorOutcome(from: result)
    }

    /// `devmachine machine doctor`: what this Mac itself is missing, for the
    /// configured self machine.
    func machineDoctor() throws -> DoctorOutcome {
        let result = try runner.runCapturing(
            executable: executable,
            args: ["--format", "json", "machine", "doctor"],
            environment: environment()
        )
        return try doctorOutcome(from: result)
    }

    // `doctor` exits 1 when a check fails — that is its normal, informative
    // result, not a command failure, so the exit code is never used to decide
    // whether this throws. Only stdout that carries nothing usable at all
    // (the command could not even start reporting) is a real failure.
    private func doctorOutcome(
        from result: (stdout: String, stderr: String, exitCode: Int32)
    ) throws -> DoctorOutcome {
        if let report = DoctorParser.parse(result.stdout) {
            return .report(report)
        }
        if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .raw(result.stdout)
        }
        let detail = result.stderr.isEmpty ? result.stdout : result.stderr
        throw DevmachineCLIError.commandFailed(detail.isEmpty ? "Devmachine CLI failed." : detail)
    }

    /// The context engine, reached as `devmachine-app`'s `context` entrypoint.
    /// A workspace session runs it over the CLI's own ssh, as that workspace's
    /// account.
    func context(workspace: String, session: String) throws -> String {
        let result = try runner.runCapturing(
            executable: executable,
            args: [
                "run", "--workspace", workspace, "--package", "devmachine-app",
                "--", "context", "--session", session,
            ],
            environment: environment()
        )
        try requireSuccess(result)
        return result.stdout
    }

    /// The same engine, run locally by the CLI on the named self machine.
    func context(machine: String, project: String) throws -> String {
        let result = try runner.runCapturing(
            executable: executable,
            args: [
                "run", "--machine", machine, "--package", "devmachine-app",
                "--", "context", "--project", project,
            ],
            environment: environment()
        )
        try requireSuccess(result)
        return result.stdout
    }

    // An app opened from the Dock inherits launchd's empty SSH agent, not the
    // shell's, so the CLI needs an explicit socket the same way a terminal
    // does: an override from Settings, else the 1Password agent if it is
    // actually there, else whatever this process inherited.
    func environment() -> [String: String] {
        var environment = processEnvironment
        let socket = RemoteCommands.sshAuthSocket(
            customSocket: customSocket, fileExists: socketFileExists, environment: processEnvironment)
        environment["SSH_AUTH_SOCK"] = socket
        return environment
    }

    private func requireSuccess(_ result: (stdout: String, stderr: String, exitCode: Int32)) throws {
        guard result.exitCode == 0 else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw DevmachineCLIError.commandFailed(detail.isEmpty ? "Devmachine CLI failed." : detail)
        }
    }
}
