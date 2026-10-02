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
            source: "release"),
        CLIPackage(
            name: "docker", scope: "machine", installedOn: ["machine main"],
            summary: "Docker Engine and the Compose plugin, from Docker's own repository.", source: "release"),
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
        packages: machinePackages)

    /// Somebody with the CLI and no server yet: no `config.yml`, so no
    /// machine and no package list to offer.
    static let noMachinesSnapshot = MachinesSnapshot.none

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
