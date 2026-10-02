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
        CLIPackage(
            name: "zsh", scope: "workspace", installedOn: ["workspace acme"],
            summary: "zsh with a prompt.", source: "release"),
    ]

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

    static let unattendedCLI = MachineUnattendedAdd.minimumCLIVersion

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
