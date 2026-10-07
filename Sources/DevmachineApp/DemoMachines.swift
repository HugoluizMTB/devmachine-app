import Foundation
import DevmachineCore

/// Invented machines and packages for Settings → Machines and the Add machine
/// wizard in demo mode.
extension DemoData {
    static let machinePackages: [CLIPackage] = [
        CLIPackage(
            name: "essentials", scope: "machine",
            installedOn: ["machine main", "machine staging"],
            summary: "What almost every machine wants, in one package: base tools, git, a firewall, "
                + "SSH with passwords kept off, Caddy to publish sites with HTTPS, and what the "
                + "Devmachine macOS app reads from a machine.",
            source: "release", platforms: ["linux"],
            needs: ["base", "git", "firewall", "ssh-hardening", "caddy", "devmachine-app"]),
        CLIPackage(
            name: "docker", scope: "machine", installedOn: ["machine main"],
            summary: "Docker Engine and the Compose plugin, from Docker's own repository.", source: "release",
            platforms: ["linux"]),
        CLIPackage(
            name: "homebrew-apps", scope: "machine", installedOn: [],
            summary: "Mac apps from Homebrew casks. Only for this Mac, never a server.", source: "release",
            platforms: ["macos"]),
        CLIPackage(
            name: "tailscale", scope: "machine", installedOn: [],
            summary: "Joins the machine to a tailnet, so it is reachable without a public address.",
            source: "release"),
        CLIPackage(
            name: "fail2ban", scope: "machine", installedOn: ["machine main"],
            summary: "fail2ban, with a jail for sshd.", source: "release"),
        CLIPackage(
            name: "cloudflare", scope: "machine", installedOn: [],
            summary: "DNS zones on Cloudflare.", source: "release"),
        CLIPackage(
            name: "acme-routes", scope: "machine", installedOn: [],
            summary: "Reverse-proxy routes for the acme apps that run outside devmachine.", source: "local"),
    ] + workspacePackages

    /// Workspace packages for the Workspaces page, named like the release's.
    static let workspacePackages: [CLIPackage] = [
        workspacePackage("workspace", "Foundation", "The account a person works in: a home nobody else can "
            + "read, a git identity and ~/dev.", on: ["acme", "globex", "initech", "umbrella"]),
        workspacePackage("dev", "Foundation", "The tools a workspace is expected to have: the GitHub CLI, bun "
            + "and Node through mise.", on: ["acme", "globex", "initech"]),
        workspacePackage("zsh", "Foundation", "zsh as the login shell, a prompt and a tmux config.",
                         on: ["acme", "globex", "initech"], variables: [
                            PackageVariable(name: "plugins", summary: "Oh My Zsh plugins to load.",
                                            default: .array([.string("git")]), type: .list),
                            PackageVariable(name: "theme", summary: "The prompt theme.", default: .string("clean"),
                                            type: .string),
                         ]),
        workspacePackage("mise", "Foundation", "mise, the per-project runtime manager, for one account.",
                         on: ["acme", "globex"]),
        workspacePackage("claude-code", "Coding agents", "The Claude Code CLI for one account. Logging in is a "
            + "person's job, once.", on: ["acme", "initech"],
            credentials: [PackageCredential(name: "claude", kind: "file", scope: "machine", shareable: true)],
            variables: [PackageVariable(name: "auto_update", summary: "Let Claude Code update itself.",
                                        default: .bool(true), type: .boolean)]),
        workspacePackage("opencode", "Coding agents", "The opencode CLI for one account.", on: ["globex"]),
        workspacePackage("pi", "Coding agents", "The Pi coding agent for one account, from its standalone release.",
                         on: []),
        workspacePackage("codex", "Coding agents", "OpenAI's Codex CLI for one account, from its standalone release.",
                         on: [], credentials: [PackageCredential(name: "codex", kind: "manual", scope: "workspace", shareable: true)]),
        workspacePackage("antigravity", "Coding agents", "Google's Antigravity CLI for one account.", on: []),
        workspacePackage("kimi-code", "Coding agents", "The Kimi Code CLI for one account.", on: []),
        workspacePackage("cline", "Coding agents", "The Cline CLI for one account.", on: []),
        workspacePackage("glab", "Developer tools", "The GitLab CLI in the account's own ~/.local/bin.", on: [],
                         credentials: [PackageCredential(name: "glab", kind: "secret", scope: "workspace", shareable: false)]),
        workspacePackage("sentry", "Developer tools", "The Sentry CLI in the account's own ~/.local/bin.", on: []),
    ]

    private static func workspacePackage(
        _ name: String, _ category: String, _ summary: String, on: [String],
        credentials: [PackageCredential] = [], variables: [PackageVariable] = []
    ) -> CLIPackage {
        CLIPackage(
            name: name, scope: "workspace", installedOn: on.map { "workspace \($0)" }, summary: summary,
            source: "release", category: category, credentials: credentials, variables: variables)
    }

    /// The configuration's workspaces with what the last sync applied:
    /// initech waits for a sync, umbrella was never synced.
    static let workspacesSnapshot = WorkspacesSnapshot(
        workspaces: [
            WorkspaceSummary(
                name: "acme", machine: "main", user: "acme",
                packages: ["dev", "zsh", "mise", "claude-code", "pi", "glab"],
                settings: ["zsh.theme": "robbyrussell"], credentials: ["claude": "own"]),
            WorkspaceSummary(name: "globex", machine: "main", user: "globex", packages: ["dev", "zsh", "mise", "opencode"]),
            WorkspaceSummary(name: "initech", machine: "main", user: "initech", packages: ["dev", "zsh", "claude-code"]),
            WorkspaceSummary(name: "umbrella", machine: "staging", user: "umbrella", packages: ["zsh"]),
        ],
        lock: PackagesLock(machines: [:], workspaces: [
            "acme": ["workspace", "mise", "dev", "zsh", "claude-code", "pi", "glab"].map {
                PackagesLock.Entry(name: $0)
            },
            "globex": ["workspace", "mise", "dev", "zsh", "opencode"].map { PackagesLock.Entry(name: $0) },
            "initech": ["workspace", "mise", "dev", "zsh"].map { PackagesLock.Entry(name: $0) },
        ]),
        defaults: ["dev", "zsh", "mise"], sharing: ["claude": "machine"], reportsSharing: true)

    static let machinesSnapshot = MachinesSnapshot(
        hasConfiguration: true,
        machines: [
            ConfiguredMachine(
                name: "main", hosts: ["100.64.0.10", "203.0.113.10"], adminUser: "root", port: 22,
                workspaces: ["acme", "globex", "initech"],
                packages: ["essentials", "docker", "fail2ban"], isSelf: false),
            ConfiguredMachine(
                name: "staging", hosts: ["203.0.113.12"], adminUser: "deploy", port: 2222,
                workspaces: ["umbrella"], packages: ["essentials"], isSelf: false),
            ConfiguredMachine(
                name: "laptop", hosts: [], adminUser: "", port: 0,
                workspaces: [], packages: [], isSelf: true),
        ],
        packages: machinePackages, cliVersion: unattendedCLI)

    /// The same configuration read by a CLI too old to add without a terminal.
    static var legacyMachinesSnapshot: MachinesSnapshot {
        var snapshot = machinesSnapshot
        snapshot.cliVersion = SemanticVersion(major: 0, minor: 7, patch: 26)
        return snapshot
    }

    /// The newest CLI the app knows: it adds unattended and sizes a Lima machine.
    static let unattendedCLI = LocalMachineSizing.minimumCLIVersion

    /// A CLI that adds unattended but makes a Lima machine at its own size.
    static var unsizedMachinesSnapshot: MachinesSnapshot {
        var snapshot = machinesSnapshot
        snapshot.cliVersion = MachineUnattendedAdd.minimumCLIVersion
        return snapshot
    }

    /// An invented Mac for the size controls, never the one capturing.
    static let macLimits = LocalMachineSizeLimits(
        cores: 10, memoryBytes: 32 << 30, freeDiskBytes: 400 << 30)

    /// Somebody with the CLI and no server yet: no `config.yml`, so no
    /// machine; a new CLI still lists the latest release's packages.
    static let noMachinesSnapshot = MachinesSnapshot(
        hasConfiguration: false, machines: [],
        packages: machinePackages.map {
            CLIPackage(
                name: $0.name, scope: $0.scope, installedOn: [], summary: $0.summary, source: $0.source,
                platforms: $0.platforms, needs: $0.needs)
        }.filter { $0.source == "release" },
        cliVersion: unattendedCLI)

    static let addMachineAgentKeys = [
        AgentKey(fingerprint: "SHA256:ZGVtbyBhZ2VudCBrZXkgb25lLCBub3QgcmVhbCAwMSE", comment: "alice@example.com",
                 type: "ED25519"),
        AgentKey(fingerprint: "SHA256:ZGVtbyBhZ2VudCBrZXkgdHdvLCBub3QgcmVhbCAwMiE", comment: "Work laptop",
                 type: "ED25519"),
    ]

    static func addMachineScan(address: String, port: String) -> MachineScan {
        MachineScan(
            address: address, port: Int(port) ?? 22, keyType: "ssh-ed25519", fingerprint: addMachineFingerprint,
            verify: "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
    }

    /// What a background run printed, partway through its steps.
    static let addMachineOutput = [
        "$ devmachine machines add --name backup --address 203.0.113.20 --fingerprint \(addMachineFingerprint) "
            + "--password-stdin --yes",
        "backup at 203.0.113.20:22 presented ssh-ed25519 host key \(addMachineFingerprint).",
        "logging in with the password to install the key /Users/alice/.ssh/devmachine_backup...",
        "the key logs in as root@203.0.113.20.",
        "turning password login off...",
        "password login is off; the key is the only way in.",
        "installing Ansible...",
        "added backup to /Users/alice/.config/devmachine/config.yml",
        "$ devmachine packages add docker --machine backup --yes",
        "added docker to machine backup",
    ]

    static let addMachineFingerprint = "SHA256:Zm9yIGEgZGVtbyBvbmx5LCBub3QgYSByZWFsIGtleTE"

    /// The Add machine wizard's terminal, partway through its steps.
    static let addMachineTranscript = """
        \u{1B}[2m$ devmachine machines add --name backup --address 203.0.113.20 --fingerprint SHA256:Zm9y… --key ~/.ssh/id_ed25519 --yes\u{1B}[0m

        backup at 203.0.113.20:22 presented ssh-ed25519 host key \(addMachineFingerprint).

        added backup to /Users/alice/.config/devmachine/config.yml

        the key /Users/alice/.ssh/id_ed25519 already logs in as root@203.0.113.20.
        turning password login off...
        password login is off; the key is the only way in.
        installing Ansible...

        \u{1B}[2m$ devmachine packages add docker --machine backup --yes\u{1B}[0m
        added docker to machine backup

        """
}

extension DemoData {
    /// Invented answers for Settings → Machines' panels: nothing is asked.
    static let machineDetailsService = MachineDetailsService(
        doctor: { machine, _ in
            .report(DoctorReport(checks: [
                DoctorCheck(name: "ssh", status: .pass, detail: "root@\(machine) answers with the trusted key"),
                DoctorCheck(name: "ansible", status: .pass, detail: "ansible-core 2.17 on the machine"),
                DoctorCheck(name: "packages", status: .warn, detail: "1 package waits for a sync: run `devmachine sync`"),
            ], ok: true))
        },
        addresses: { machine in
            MachineAddresses.parse("""
                {"machine":"\(machine)","addresses":[
                 {"address":"100.64.0.10","source":"tailscale:\(machine)","package":"tailscale"},
                 {"address":"203.0.113.10","source":"203.0.113.10","package":""}],
                 "dropped":[{"source":"\(machine).example.com","reason":"no such host"}]}
                """)!
        },
        credentials: { _ in
            MachineCredentials.parse("""
                {"credentials":[
                 {"key":"claude","name":"claude","kind":"file","package":"claude-code","status":"present"},
                 {"key":"acme/gh","name":"gh","kind":"manual","package":"dev","workspace":"acme","status":"missing",
                  "fix":"devmachine login gh --workspace acme"}]}
                """)!
        },
        editLocation: { _, _ in },
        passwordLogin: { machine in
            MachinePasswordLogin.parse("""
                {"machine":"\(machine)","default":false,"drop_in":true,
                 "accounts":[{"user":"alice","password_login":true},{"user":"bob","password_login":false}],
                 "keep":["alice"]}
                """)!
        },
        changePasswordLogin: { _, _ in })
}
