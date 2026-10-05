#if DEBUG
import AppKit
import SwiftUI
import DevmachineCore

/// Debug builds only. Settings → Machines' network map and per-machine
/// actions, for `DEVMACHINE_DEMO_WALK=machines-map`: a fleet across three
/// locations, one machine, eight machines, a selected machine, each inline
/// panel, a Lima start in the corner, the location editor, and the wizard's
/// location field on a current and an older CLI. Nothing runs.
@MainActor
enum DemoMachinesMap {
    static let screens: [DemoSnapshots.Screen] = [
        .init(id: "map-fleet", fileName: "160-machines-map.png", settleNanoseconds: 700_000_000),
        .init(id: "map-selected", fileName: "161-machines-map-selected.png", settleNanoseconds: 700_000_000),
        .init(id: "map-check", fileName: "162-machines-check.png", settleNanoseconds: 700_000_000),
        .init(id: "map-addresses", fileName: "163-machines-addresses.png", settleNanoseconds: 700_000_000),
        .init(id: "map-credentials", fileName: "164-machines-credentials.png", settleNanoseconds: 700_000_000),
        .init(id: "map-lima-job", fileName: "165-machines-lima-job.png", settleNanoseconds: 700_000_000),
        .init(id: "map-one", fileName: "166-machines-map-one.png", settleNanoseconds: 700_000_000),
        .init(id: "map-many", fileName: "167-machines-map-many.png", settleNanoseconds: 700_000_000),
        .init(id: "map-location-editor", fileName: "168-machines-location-editor.png", settleNanoseconds: 300_000_000),
        .init(id: "map-wizard-location", fileName: "169-add-machine-location.png", settleNanoseconds: 500_000_000),
        .init(id: "map-wizard-old-cli", fileName: "170-add-machine-location-old-cli.png",
              settleNanoseconds: 500_000_000),
    ]

    static func handles(_ id: String) -> Bool { screens.contains { $0.id == id } }

    static func reset() {
        DemoSnapshots.machinesSelected = nil
    }

    static func prepare(_ id: String, model: AppModel, caddy: CaddyStore) async {
        let snapshot = snapshot(for: id)
        MachinesStore.shared.seedDemo(snapshot)
        PackagesStore.shared.seedDemo(DemoPackages.snapshot(after: .saved))
        DemoSnapshots.machinesSelected = ["map-selected", "map-check", "map-addresses", "map-credentials",
                                          "map-lima-job"].contains(id) ? selection(for: id) : nil
        model.jobs.seedDemo(id == "map-lima-job" ? [limaJob] : [])
        let details = MachineDetailsStore.shared
        await details.seedDemo(open: nil, machine: "", isSelf: false)
        if id.hasPrefix("map-wizard") {
            await prepareWizard(old: id == "map-wizard-old-cli", model: model, snapshot: snapshot)
            return
        }
        guard id != "map-location-editor" else { return }
        DemoSnapshots.setupInitialSection = .machines
        model.showPage(.setup)
        try? await Task.sleep(nanoseconds: 300_000_000)
        caddy.show(machines: snapshot.machines.map { CLIMachine(name: $0.name, isSelf: $0.isSelf) },
                   states: sites(for: id), selected: "main")
        switch id {
        case "map-check": await details.seedDemo(open: .check, machine: "main", isSelf: false)
        case "map-addresses": await details.seedDemo(open: .addresses, machine: "homebox", isSelf: false)
        case "map-credentials": await details.seedDemo(open: .credentials, machine: "main", isSelf: false)
        default: break
        }
    }

    /// The location editor is a popover, a window of its own; it is drawn
    /// on its own here.
    static func locationEditorView() -> NSView {
        let machine = fleet.machines.first { $0.name == "homebox" }!
        let view = MachineLocationEditor(
            machine: machine, takesLocation: true, knownLocations: ["local", "hostinger", "home"],
            details: MachineDetailsStore.shared, done: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        return hosting
    }

    private static func selection(for id: String) -> String {
        switch id {
        case "map-addresses": return "homebox"
        case "map-lima-job": return "lab"
        default: return "main"
        }
    }

    private static func prepareWizard(old: Bool, model: AppModel, snapshot: MachinesSnapshot) async {
        var seeded = snapshot
        if old { seeded.cliVersion = SemanticVersion(major: 0, minor: 7, patch: 29) }
        MachinesStore.shared.seedDemo(seeded)
        let state = AddMachineModel.shared
        state.startOver()
        model.showPage(.addMachine)
        try? await Task.sleep(nanoseconds: 150_000_000)
        state.startOver()
        if old {
            state.wizard.choose(.server)
            state.wizard.draft.name = "backup"
            state.wizard.draft.location = "home"
            state.wizard.draft.address = "203.0.113.20"
        } else {
            state.wizard.choose(.localVM)
            state.wizard.draft.name = "lab2"
        }
    }

    // MARK: - Data

    static func snapshot(for id: String) -> MachinesSnapshot {
        switch id {
        case "map-one": return one
        case "map-many": return many
        default: return fleet
        }
    }

    private static func machine(
        _ name: String, _ location: String?, hosts: [String], workspaces: [String] = [],
        packages: [String] = ["essentials"], isSelf: Bool = false, user: String = "root", port: Int = 22
    ) -> ConfiguredMachine {
        ConfiguredMachine(
            name: name, hosts: hosts, adminUser: user, port: port, workspaces: workspaces, packages: packages,
            isSelf: isSelf, reportedLocation: location)
    }

    static let fleet = MachinesSnapshot(
        hasConfiguration: true,
        machines: [
            machine("main", "hostinger", hosts: ["100.64.0.10", "203.0.113.10"],
                    workspaces: ["acme", "globex", "initech"], packages: ["essentials", "docker", "tailscale"]),
            machine("staging", "hostinger", hosts: ["203.0.113.12"], workspaces: ["beta"]),
            machine("homebox", "home", hosts: ["tailscale:homebox"], workspaces: ["umbrella"],
                    packages: ["docker", "tailscale"]),
            machine("lab", "local", hosts: ["127.0.0.1"], workspaces: ["acme-lab"], port: 60022),
            machine("laptop", "local", hosts: [], packages: [], isSelf: true, user: ""),
        ],
        packages: DemoData.machinePackages, cliVersion: MachineLocation.minimumCLIVersion)

    static let one = MachinesSnapshot(
        hasConfiguration: true,
        machines: [machine("main", "hostinger", hosts: ["203.0.113.10"], workspaces: ["acme"])],
        packages: DemoData.machinePackages, cliVersion: MachineLocation.minimumCLIVersion)

    static let many = MachinesSnapshot(
        hasConfiguration: true,
        machines: [
            machine("main", "hostinger", hosts: ["100.64.0.10", "203.0.113.10"], workspaces: ["acme", "globex"]),
            machine("edge", "hostinger", hosts: ["203.0.113.14"], packages: ["caddy"]),
            machine("staging", "hostinger", hosts: ["203.0.113.12"], workspaces: ["beta"], packages: ["docker"]),
            machine("db", "other cloud", hosts: ["100.64.0.21"], packages: ["postgres"]),
            machine("ci", "other cloud", hosts: ["203.0.113.30"], workspaces: ["runner"], packages: ["docker"]),
            machine("homebox", "home", hosts: ["tailscale:homebox"], workspaces: ["umbrella"], packages: ["docker"]),
            machine("nas", "home", hosts: ["100.64.0.30"], packages: ["tailscale"]),
            machine("lab", "local", hosts: ["127.0.0.1"], workspaces: ["acme-lab"], port: 60022),
        ],
        packages: DemoData.machinePackages, cliVersion: MachineLocation.minimumCLIVersion)

    private static func row(_ host: String, _ workspace: String) -> SubdomainRow {
        SubdomainRow(
            site: ExposedSite(host: host, port: 3000, workspace: workspace, status: .published),
            resolvedWorkspace: workspace, containerName: nil)
    }

    static func sites(for id: String) -> [String: MachineSitesState] {
        switch id {
        case "map-one":
            return ["main": MachineSitesState(rows: [row("app.acme.example.com", "acme")], hasLoaded: true)]
        case "map-many":
            return [
                "main": MachineSitesState(rows: [row("app.acme.example.com", "acme"),
                                                 row("media.example.com", "umbrella")], hasLoaded: true),
                "edge": MachineSitesState(rows: [row("ci.example.com", "runner"), row("beta.example.com", "beta"),
                                                 row("docs.example.com", "globex")], hasLoaded: true),
            ]
        default:
            return [
                "main": MachineSitesState(rows: [row("app.acme.example.com", "acme"),
                                                 row("api.acme.example.com", "acme"),
                                                 row("media.example.com", "umbrella")], hasLoaded: true),
                "staging": MachineSitesState(rows: [row("beta.example.com", "beta")], hasLoaded: true),
            ]
        }
    }

    private static var limaJob: MachineJob {
        var log = JobLog()
        log.append(contentsOf: ["$ devmachine machines start lab", "INFO[0000] Starting the instance \"lab\"",
                                "INFO[0004] Waiting for the essential requirement 1 of 3: \"ssh\""])
        let steps = [LocalMachineCommand.start.arguments(machine: "lab")]
        return MachineJob(
            id: UUID(), plan: MachineJobPlan(machine: "lab", title: LocalMachineCommand.start.title(machine: "lab"),
                                             steps: steps),
            phase: .running(step: 0), log: log, request: nil, expanded: true,
            currentCommand: "devmachine " + steps[0].joined(separator: " "))
    }
}
#endif
