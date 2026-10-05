#if DEBUG
import AppKit
import DevmachineCore

/// The Packages walk (`DEVMACHINE_DEMO_WALK=packages`): Settings → Packages
/// for every machine, then `main` with one install and one removal ticked,
/// the confirm, and the sync it asks for in the corner, pending, running,
/// done and failed. The store and the corner are seeded; nothing runs.
@MainActor
enum DemoPackages {
    enum Moment {
        case none, saved, synced
    }

    static let target = PackageTarget.machine("main", isSelf: false)

    static let screenIDs: Set<String> = [
        "packages-all", "packages-selected", "packages-confirm", "packages-pending", "packages-running",
        "packages-succeeded", "packages-failed",
    ]

    static func handles(_ id: String) -> Bool { screenIDs.contains(id) }

    static func prepare(_ id: String, model: AppModel, store: PackagesStore = .shared) {
        store.seedDemo(snapshot(after: moment(for: id)))
        DemoSnapshots.packagesInitialPage = page(for: id)
        model.jobs.seedDemo(phase(for: id).map { [job($0)] } ?? [])
        DemoSnapshots.setupInitialSection = .packages
        model.showPage(.setup)
    }

    static func reset() {
        DemoSnapshots.packagesInitialPage = PackagesPageState()
        DemoSnapshots.setupInitialSection = .general
    }

    static func page(for id: String) -> PackagesPageState {
        guard id != "packages-all" else { return PackagesPageState() }
        var page = PackagesPageState()
        if id == "packages-selected" || id == "packages-confirm" {
            page.toggleExpanded("postgres")
            page.rowDestinations = [target]
            page.toggle("postgres")
            page.toggle("nodejs")
            page.bulkDestinations = [target, .workspace("acme", machine: "main")]
        }
        return page
    }

    private static func moment(for id: String) -> Moment {
        switch id {
        case "packages-all", "packages-selected", "packages-confirm": return .none
        case "packages-succeeded": return .synced
        default: return .saved
        }
    }

    private static func phase(for id: String) -> MachineJobPhase? {
        switch id {
        case "packages-pending": return .pending
        case "packages-running": return .running(step: 0)
        case "packages-succeeded": return .succeeded(SyncSummary(ok: 14, changed: 2, failed: 0))
        case "packages-failed": return .failed(cause: "1 task(s) failed on main: exit status 2")
        default: return nil
        }
    }

    /// The confirm the page asks before `packages add|rm`, drawn by the alert
    /// AppKit shows for it, with the page's own words.
    static func confirmView() -> NSView {
        let batch = PackagesSettingsView.plan(
            ["postgres", "nodejs"], on: [target, .workspace("acme", machine: "main")], .install,
            snapshot: snapshot(after: .none))
        let alert = NSAlert()
        alert.messageText = PackagesSettingsView.confirmTitle(.install)
        alert.informativeText = PackagesSettingsView.confirmMessage(batch, action: .install)
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.window.appearance = NSAppearance(named: .darkAqua)
        alert.layout()
        if DemoSnapshots.isHidden { alert.window.alphaValue = 0 }
        alert.window.orderFrontRegardless()
        alert.window.displayIfNeeded()
        return alert.window.contentView ?? NSView()
    }

    static func snapshot(after moment: Moment) -> PackagesSnapshot {
        let saved = moment != .none
        let entries = [
            entry("caddy", category: "web", summary: "Serves published sites over HTTPS.", on: ["machine main"]),
            entry("docker", category: "containers", summary: "Docker Engine and the compose plugin.",
                  on: ["machine main", "machine staging"]),
            entry("essentials", category: "base", summary: "The base every machine keeps.", needs: ["git"],
                  on: ["machine main", "machine staging"]),
            entry("git", category: "base", summary: "Git from the distribution."),
            entry("hostinger", category: "dns", summary: "DNS zones on Hostinger.", credentials: ["hostinger"]),
            entry("nodejs", scope: "workspace", category: "languages", summary: "Node.js LTS for the workspace.",
                  on: ["workspace acme"]),
            entry("postgres", category: "databases", summary: "PostgreSQL server with a local admin role.",
                  on: saved ? ["machine main"] : []),
            entry("redis", category: "databases", summary: "Redis on localhost.",
                  on: saved ? [] : ["machine main"]),
            entry("tailscale", category: "network", summary: "Joins the machine to the tailnet.", on: ["machine main"]),
            entry("workspace", scope: "workspace", category: "base", summary: "The workspace's Linux account."),
            entry("acme-tools", source: "local", category: "tools", summary: "acme's own scripts."),
        ]
        var main = ["caddy", "docker", "essentials", "git"]
        main += moment == .synced ? ["postgres", "tailscale"] : ["redis"]
        let lock = PackagesLock(
            appliedAt: "1",
            machines: ["main": main.map { PackagesLock.Entry(name: $0) },
                       "staging": ["docker", "essentials", "git"].map { PackagesLock.Entry(name: $0) }],
            workspaces: ["acme": ["workspace", "nodejs"].map { PackagesLock.Entry(name: $0) }])
        return PackagesSnapshot(
            entries: entries,
            targets: [target, .machine("staging", isSelf: false), .workspace("acme", machine: "main"),
                      .workspace("beta", machine: "main")],
            lock: lock, cliVersion: SemanticVersion("0.7.28"), configDirectory: "~/.config/devmachine")
    }

    static func job(_ phase: MachineJobPhase) -> MachineJob {
        let request = SyncRequest(machine: "main", tags: ["postgres"], full: true, reasons: ["Packages"])
        let steps = phase == .pending ? [] : [request.arguments(full: true)]
        var log = JobLog()
        log.append(contentsOf: lines(phase))
        return MachineJob(
            id: UUID(), plan: MachineJobPlan(machine: "main", title: "Sync main", steps: steps), phase: phase,
            log: log, request: request, expanded: phase != .pending && !isSuccess(phase),
            currentCommand: steps.first.map { "devmachine " + $0.joined(separator: " ") })
    }

    private static func isSuccess(_ phase: MachineJobPhase) -> Bool {
        if case .succeeded = phase { return true }
        return false
    }

    private static func lines(_ phase: MachineJobPhase) -> [String] {
        guard phase != .pending else { return [] }
        let plan = [
            "$ devmachine sync --machine main --yes",
            "main: caddy, docker, essentials, git, postgres, tailscale", "",
            "PLAY [devmachine] *************************************************", "",
            "TASK [Gathering Facts] ********************************************", "ok: [devmachine]", "",
            "TASK [postgres : Install the server] ******************************", "changed: [devmachine]", "",
            "TASK [tailscale : Join the tailnet] *******************************",
        ]
        switch phase {
        case .failed:
            return plan + [
                #"fatal: [devmachine]: FAILED! => {"msg": "Could not resolve host: pkgs.tailscale.com"}"#,
                "error: 1 task(s) failed on main: exit status 2",
            ]
        case .succeeded:
            return plan + ["changed: [devmachine]", "", "main: ok=14 changed=2 failed=0"]
        default:
            return plan
        }
    }

    private static func entry(
        _ name: String, scope: String = "machine", source: String = "catalog", category: String, summary: String,
        needs: [String] = [], credentials: [String] = [], on installedOn: [String] = []
    ) -> PackageEntry {
        PackageEntry(
            name: name, scope: scope, source: source, summary: summary, category: category,
            platforms: scope == "machine" ? ["linux"] : [], needs: needs, credentialNames: credentials,
            installedOn: installedOn)
    }
}
#endif
