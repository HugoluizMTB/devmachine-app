import Foundation
import DevmachineCore
import HarnessUsageKit

/// Every invented value the demo build shows. Nothing here is a real
/// workspace, host, repo or credential — see `CLAUDE.md` "No real data".
/// Each store reads a slice of this in place of a live fetch when
/// `DemoMode.isActive`; nothing here ever touches disk or the network.
enum DemoData {
    // MARK: Workspaces and sessions

    static let machineName = "main"
    static let machineAddress = "203.0.113.10"

    static let workspaces: [Workspace] = [
        Workspace(name: "acme", alias: "acme-devmachine"),
        Workspace(name: "globex", alias: "globex-devmachine"),
        Workspace(name: "initech", alias: "initech-devmachine"),
        Workspace(name: "umbrella", alias: "umbrella-devmachine"),
    ]

    static let sessionsByAlias: [String: [TmuxSession]] = [
        "acme-devmachine": [
            TmuxSession(name: "claude — payments refactor", windows: 3, harnesses: [.claude]),
            TmuxSession(name: "codex — landing page", windows: 2, harnesses: [.codex]),
            TmuxSession(name: "api — tests", windows: 1, harnesses: []),
            TmuxSession(name: "web — dev server", windows: 1, harnesses: []),
        ],
        "globex-devmachine": [
            TmuxSession(name: "dashboard — tests", windows: 1, harnesses: []),
            TmuxSession(name: "claude", windows: 2, harnesses: [.claude]),
        ],
        "initech-devmachine": [
            TmuxSession(name: "codex", windows: 1, harnesses: [.codex]),
        ],
        "umbrella-devmachine": [
            TmuxSession(name: "web — dev server", windows: 1, harnesses: []),
            TmuxSession(name: "pi — docs", windows: 1, harnesses: [.pi]),
            TmuxSession(name: "agy — search", windows: 1, harnesses: [.antigravity]),
            TmuxSession(name: "opencode — api", windows: 1, harnesses: [.opencode]),
            TmuxSession(name: "kimi — tests", windows: 1, harnesses: [.kimi]),
            TmuxSession(name: "cline — cleanup", windows: 1, harnesses: [.cline]),
            TmuxSession(name: "herdr — agents", windows: 1, harnesses: [.herdr]),
        ],
    ]

    static let operatorPath = "/Users/alice/.config/devmachine"

    static let localSessions: [LocalSession] = [
        LocalSession(name: Workspace.operatorSession, path: operatorPath),
        LocalSession(name: "claude", path: "/Users/alice/dev/acme-app"),
        LocalSession(name: "codex", path: "/Users/alice/dev/globex-dashboard"),
    ]

    static let localSessionHarnesses: [String: Set<HarnessID>] = [
        Workspace.operatorSession: [.claude],
        "claude": [.claude],
        "codex": [.codex],
    ]

    // MARK: Terminal transcripts

    // Lines are kept short (well under 45 columns) and few (at most 24): a
    // session grid cell is narrow and short, and a terminal wraps mid-word and
    // scrolls its first lines away — a transcript that reads fine alone
    // breaks once four panes share a window.
    private static let claudeTranscript = """
    \u{1B}[1m\u{1B}[36m● Claude Code\u{1B}[0m — payments refactor

    \u{1B}[2mReading ChargeService.swift\u{1B}[0m
    \u{1B}[2mReading RefundService.swift\u{1B}[0m

    Found the retry loop that double-
    charges on a gateway timeout.

    \u{1B}[1mTodo\u{1B}[0m
      \u{1B}[32m✔\u{1B}[0m Reproduce with a fake gateway
      \u{1B}[32m✔\u{1B}[0m Add an idempotency key
      \u{1B}[33m→\u{1B}[0m Cover the retry path in a test
      \u{1B}[2m○ Update CHANGELOG\u{1B}[0m

    \u{1B}[2m~ ChargeService.swift\u{1B}[0m
    \u{1B}[31m-   try gateway.charge(order)\u{1B}[0m
    \u{1B}[32m+   try gateway.charge(order,\u{1B}[0m
    \u{1B}[32m+     idempotencyKey: order.id)\u{1B}[0m

    \u{1B}[2m$\u{1B}[0m swift test --filter Charge
    \u{1B}[32mTest Suite passed\u{1B}[0m at 09:14:02.
    \u{1B}[32m  6 tests, 0 failures\u{1B}[0m
    \u{1B}[36m❯\u{1B}[0m
    """

    private static let codexTranscript = """
    \u{1B}[1m\u{1B}[35m● Codex\u{1B}[0m — landing page

    \u{1B}[2m› lazy-loading the hero video\u{1B}[0m

    \u{1B}[2mediting Hero.tsx\u{1B}[0m
    \u{1B}[31m- <video autoPlay src={hero} />\u{1B}[0m
    \u{1B}[32m+ <video autoPlay src={hero}\u{1B}[0m
    \u{1B}[32m+   preload="none" loading="lazy" />\u{1B}[0m

    \u{1B}[2m$\u{1B}[0m npm run build
    \u{1B}[32mvite v5 building...\u{1B}[0m
    \u{1B}[32m✓ 412 modules transformed.\u{1B}[0m
    \u{1B}[32m✓ built in 3.81s\u{1B}[0m

    \u{1B}[35m❯\u{1B}[0m
    """

    private static let testRunTranscript = """
    \u{1B}[2m$\u{1B}[0m swift test
    \u{1B}[2mBuilding for debugging...\u{1B}[0m
    \u{1B}[2mBuild complete! (4.92s)\u{1B}[0m

    \u{1B}[32m✔\u{1B}[0m DashboardViewTests (18 tests)
    \u{1B}[32m✔\u{1B}[0m ExportServiceTests (9 tests)
    \u{1B}[32m✔\u{1B}[0m WebhookRouterTests (14 tests)

    \u{1B}[32mAll tests passed\u{1B}[0m at 09:20:11.
    \u{1B}[32m41 tests, 0 failures, 0.61s\u{1B}[0m

    \u{1B}[36m$\u{1B}[0m
    """

    private static let devServerTranscript = """
    \u{1B}[2m$\u{1B}[0m npm run dev

    \u{1B}[32m  VITE v5.2.0\u{1B}[0m  ready in 318 ms

    \u{1B}[2m  ➜\u{1B}[0m  Local:  \u{1B}[36mlocalhost:5173\u{1B}[0m
    \u{1B}[2m  ➜\u{1B}[0m  Net:    \u{1B}[36m100.64.0.12:5173\u{1B}[0m

    \u{1B}[2m9:24 AM\u{1B}[0m \u{1B}[36m[vite]\u{1B}[0m hmr App.tsx
    \u{1B}[2m9:24 AM\u{1B}[0m \u{1B}[36m[vite]\u{1B}[0m hmr Nav.tsx

    \u{1B}[36m$\u{1B}[0m
    """

    private static let operatorTranscript = """
    \u{1B}[1m\u{1B}[36m● Claude Code\u{1B}[0m — ~/.config/devmachine

    \u{1B}[2m>\u{1B}[0m Add a workspace globex with claude-code
      and sync it.

    \u{1B}[2mReading AGENTS.md\u{1B}[0m
    \u{1B}[2mReading config.yml\u{1B}[0m

    \u{1B}[2m$\u{1B}[0m devmachine workspaces new globex
    \u{1B}[32m✓\u{1B}[0m workspace globex added to config.yml

    \u{1B}[2m$\u{1B}[0m devmachine packages add claude-code --workspace globex
    \u{1B}[32m✓\u{1B}[0m claude-code added to globex

    \u{1B}[2m$\u{1B}[0m devmachine sync --yes
    \u{1B}[2mPLAY RECAP\u{1B}[0m
    main  : \u{1B}[32mok=86\u{1B}[0m  \u{1B}[33mchanged=12\u{1B}[0m  \u{1B}[32mfailed=0\u{1B}[0m

    globex is ready, with Claude Code installed.
    Open it with \u{1B}[1mdevmachine ssh globex\u{1B}[0m.

    \u{1B}[36m❯\u{1B}[0m
    """

    /// One static transcript per demo session, chosen by what the session's
    /// name and kind suggest — this is cosmetic only, so a name that does not
    /// match anything falls back to a plain shell.
    @MainActor static func terminalTranscript(for kind: TerminalKind) -> String {
        // A live pane's text always arrives through a PTY, which turns a
        // program's bare "\n" into "\r\n" — a carriage return as well as a
        // line feed. `feed(text:)` skips the PTY, so a Swift multi-line
        // string's plain "\n" only moves the cursor down a row, at whatever
        // column it was already at, leaving every line after the first
        // starting mid-row instead of at the left edge.
        //
        // The leading "cursor home, clear screen" sequence is what a real
        // shell sends on start too, so the pane opens at the top-left the
        // same way a live session does. Clearing the scrollback as well keeps
        // a replayed transcript from stacking the previous copy above it.
        let typed = typedAtPrompt[kind].map { " " + $0 } ?? ""
        let transcript = transcriptOverride[kind] ?? rawTranscript(for: kind)
        return "\u{1B}[H\u{1B}[2J\u{1B}[3J"
            + transcript.replacingOccurrences(of: "\n", with: "\r\n") + typed
    }

    /// Text sitting at a session's prompt, not yet sent, the way an upload
    /// leaves its path for the person to finish the sentence. Set only by the
    /// screenshot walk, for one screen.
    @MainActor static var typedAtPrompt: [TerminalKind: String] = [:]

    /// A session's whole transcript, in place of the one its name picks.
    /// Set only by the site walk, which feeds a terminal step by step.
    @MainActor static var transcriptOverride: [TerminalKind: String] = [:]

    private static func rawTranscript(for kind: TerminalKind) -> String {
        switch kind {
        case let .remote(_, session):
            let lowered = session.lowercased()
            if lowered.contains("claude") { return claudeTranscript }
            if lowered.contains("codex") { return codexTranscript }
            if lowered.contains("test") { return testRunTranscript }
            if lowered.contains("dev") || lowered.contains("web") { return devServerTranscript }
            return testRunTranscript
        case let .local(session, _):
            let lowered = session.lowercased()
            if session == MachineStepRunner.sessionName { return addMachineTranscript }
            if lowered.contains("claude") { return claudeTranscript }
            if lowered.contains("codex") { return codexTranscript }
            return operatorTranscript
        }
    }

    // MARK: Subdomains

    static let domain = "acme.example.com"

    /// Two servers with their own sites — acme on one, globex on the other —
    /// and this Mac, which has nothing to publish from.
    static let subdomainMachines: [CLIMachine] = [
        CLIMachine(name: "main", isSelf: false),
        CLIMachine(name: "staging", isSelf: false),
        CLIMachine(name: "laptop", isSelf: true),
    ]

    static let subdomainSelectedMachine = "main"

    /// umbrella lives on a machine on the desk with no Caddy: main publishes
    /// it with `--via`.
    static let publishPlaces = PublishPlaces(
        servingMachines: ["main", "staging"],
        machineOf: ["acme": "main", "globex": "staging", "initech": "main", "umbrella": "lab"])

    static let subdomainRows: [SubdomainRow] = [
        SubdomainRow(
            site: ExposedSite(host: "app.acme.example.com", port: 3000, workspace: "acme", status: .published),
            resolvedWorkspace: "acme", containerName: "web"),
        SubdomainRow(
            site: ExposedSite(host: "api.acme.example.com", port: 8080, workspace: "acme", status: .published),
            resolvedWorkspace: "acme", containerName: "api"),
        SubdomainRow(
            site: ExposedSite(host: "docs.acme.example.com", port: 4100, workspace: "acme", status: .pending),
            resolvedWorkspace: "acme", containerName: nil),
    ]

    static let stagingSubdomainRows: [SubdomainRow] = [
        SubdomainRow(
            site: ExposedSite(host: "staging.globex.example.com", port: 4000, workspace: "globex", status: .published),
            resolvedWorkspace: "globex", containerName: "dashboard"),
        SubdomainRow(
            site: ExposedSite(host: "api.globex.example.com", port: 8000, workspace: "globex", status: .pending),
            resolvedWorkspace: "globex", containerName: nil),
    ]

    static let subdomainStates: [String: MachineSitesState] = [
        "main": MachineSitesState(rows: subdomainRows, hasLoaded: true),
        "staging": MachineSitesState(rows: stagingSubdomainRows, hasLoaded: true),
        "laptop": MachineSitesState(hasLoaded: true, notSetUpMessage: CaddyService.selfMessage("laptop")),
    ]

    static let dnsProviders = ["cloudflare", "hostinger"]

    /// Which DNS setup state the Subdomains page shows: `ready` everywhere
    /// but the `dns-setup` walk.
    enum DNSScenario {
        case ready, noneInstalled, notSynced, noZones
    }

    @MainActor static var dnsScenario = DNSScenario.ready

    @MainActor static var dnsAnswers: [DNSProviderAnswer] {
        switch dnsScenario {
        case .ready:
            return dnsProviders.map { DNSProviderAnswer(name: $0, zones: ["example.com"], error: nil) }
        case .noneInstalled, .notSynced:
            return []
        case .noZones:
            return [DNSProviderAnswer(name: "hostinger", zones: [], error: nil)]
        }
    }

    @MainActor static var dnsPackages: [CLIPackage] {
        let declared: [String]
        switch dnsScenario {
        case .ready: declared = dnsProviders
        case .noneInstalled: declared = []
        case .notSynced, .noZones: declared = ["hostinger"]
        }
        return ["cloudflare", "hostinger"].map { name in
            CLIPackage(
                name: name, scope: "machine",
                installedOn: declared.contains(name) ? ["machine \(machineName)"] : [],
                summary: "DNS zones on \(name == "cloudflare" ? "Cloudflare" : "Hostinger").",
                kind: "dns", category: "DNS",
                credentials: [PackageCredential(name: name, kind: "secret", scope: "machine")])
        }
    }

    static let dnsRecordsByProvider: [String: [DNSRecordRow]] = [
        "cloudflare": [
            DNSRecordRow(name: "app.acme.example.com", type: "A", value: machineAddress, ttl: 300),
            DNSRecordRow(name: "api.acme.example.com", type: "A", value: machineAddress, ttl: 300),
            DNSRecordRow(name: "acme.example.com", type: "TXT", value: "v=spf1 -all", ttl: 3600),
        ],
        "hostinger": [
            DNSRecordRow(name: "globex.example.com", type: "A", value: machineAddress, ttl: 3600),
            DNSRecordRow(name: "staging.globex.example.com", type: "CNAME", value: "globex.example.com", ttl: 3600),
        ],
    ]

    // MARK: Previews

    static func previewTargets(for place: PreviewPlace) -> [PreviewTarget] {
        switch place {
        case .thisMac:
            return PreviewTargets.local([
                ListeningPort(port: 4000, command: "ruby"), ListeningPort(port: 5173, command: "node"),
            ])
        case let .workspace(name):
            let user = name
            return PreviewTargets.remote(
                workspace: name, user: user, sites: subdomainRows.map(\.site) + stagingSubdomainRows.map(\.site),
                ports: [PortOwner(port: 3000, owner: "acme"), PortOwner(port: 5173, owner: "acme"),
                        PortOwner(port: 4000, owner: "globex")],
                containers: [])
        }
    }

    static let previewBaseURL = URL(string: "http://localhost:3000/")!

    static let previewPage = """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>Acme</title>
    <style>
    body{margin:0;font:16px -apple-system,system-ui,sans-serif;color:#1d2330;background:#f6f4ef}
    nav{display:flex;justify-content:space-between;align-items:center;padding:22px 48px}
    nav b{font-size:20px;letter-spacing:-.02em}
    nav span{margin-left:24px;color:#5b6272}
    header{padding:72px 48px 40px;max-width:720px}
    h1{font-size:52px;line-height:1.05;letter-spacing:-.03em;margin:0 0 18px}
    p{font-size:19px;line-height:1.5;color:#4a5263;margin:0 0 28px}
    a.cta{display:inline-block;background:#1d2330;color:#fff;text-decoration:none;padding:13px 22px;border-radius:10px}
    .cards{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;padding:24px 48px 64px}
    .card{background:#fff;border-radius:14px;padding:22px;box-shadow:0 1px 2px rgba(0,0,0,.06)}
    .card h3{margin:0 0 8px;font-size:17px}.card div{color:#5b6272;font-size:15px;line-height:1.45}
    </style></head>
    <body>
    <nav><b>acme</b><div><span>Pricing</span><span>Docs</span><span>Sign in</span></div></nav>
    <header><h1>Payments that never charge twice.</h1>
    <p>Idempotent checkout, retries that are safe by default, and a dashboard your support team will like.</p>
    <a class="cta" href="#">Start free</a></header>
    <section class="cards">
    <div class="card"><h3>Safe retries</h3><div>Every charge carries a key, so a timeout never becomes a second charge.</div></div>
    <div class="card"><h3>Refunds in one call</h3><div>Full or partial, with the reason kept next to the order.</div></div>
    <div class="card"><h3>Webhooks you can trust</h3><div>Signed, retried, and replayable from the dashboard.</div></div>
    </section>
    </body></html>
    """

    // MARK: Pull requests

    static let pullRequests: [PullRequest] = [
        PullRequest(
            number: 412, title: "Fix double-charge on gateway timeout", repo: "acme/api",
            url: "https://github.com/acme/api/pull/412", isDraft: false,
            reviewDecision: "APPROVED", headRefName: "fix-charge-retry", baseRefName: "main", ci: .success),
        PullRequest(
            number: 89, title: "Lazy-load the hero video", repo: "acme/web",
            url: "https://github.com/acme/web/pull/89", isDraft: false,
            reviewDecision: "REVIEW_REQUIRED", headRefName: "hero-lazy-load", baseRefName: "main", ci: .pending),
        PullRequest(
            number: 27, title: "Add export-to-CSV on the dashboard", repo: "globex/dashboard",
            url: "https://github.com/globex/dashboard/pull/27", isDraft: true,
            reviewDecision: "REVIEW_REQUIRED", headRefName: "csv-export", baseRefName: "main", ci: .pending),
        PullRequest(
            number: 3, title: "Bump the webhook signing key rotation to 30 days", repo: "acme/api",
            url: "https://github.com/acme/api/pull/3", isDraft: false,
            reviewDecision: "CHANGES_REQUESTED", headRefName: "rotate-webhook-key", baseRefName: "main", ci: .failure),
    ]

    /// Shown under the Home clock instead of this Mac's own name.
    static let macName = "acme-mbp"

    // MARK: Stats

    private static func snapshot(
        loadFactor: Double, users: [UserRAM], containers: [ContainerStat], dockerAvailable: Bool = true
    ) -> StatsSnapshot {
        StatsSnapshot(
            collectedAt: ISO8601DateFormatter().string(from: Date()),
            memory: .init(totalBytes: 16 * 1_000_000_000, usedBytes: Int64(Double(9_600_000_000) * loadFactor), availableBytes: 6_400_000_000),
            swap: .init(totalBytes: 2 * 1_000_000_000, usedBytes: 128_000_000),
            disk: .init(path: "/", usedBytes: 84_000_000_000, availableBytes: 116_000_000_000, usedPercent: 42),
            load: .init(load1: 1.2 * loadFactor, load5: 0.9 * loadFactor, load15: 0.7 * loadFactor),
            docker: .init(available: dockerAvailable, containers: containers),
            users: users,
            ports: [PortOwner(port: 3000, owner: "acme"), PortOwner(port: 8080, owner: "acme"),
                    PortOwner(port: 4000, owner: "globex")],
            errors: [])
    }

    static let statsSnapshots: [String: StatsSnapshot] = [
        "main": snapshot(
            loadFactor: 1.0,
            users: [UserRAM(user: "acme", rssBytes: 2_100_000_000), UserRAM(user: "globex", rssBytes: 1_400_000_000),
                    UserRAM(user: "initech", rssBytes: 900_000_000), UserRAM(user: "umbrella", rssBytes: 600_000_000)],
            containers: [
                ContainerStat(name: "postgres", memUsedBytes: 512_000_000, memLimitBytes: 1_000_000_000, cpuPercent: 4.1, owner: "acme"),
                ContainerStat(name: "redis", memUsedBytes: 96_000_000, memLimitBytes: 256_000_000, cpuPercent: 0.8, owner: "acme"),
                ContainerStat(name: "web", memUsedBytes: 210_000_000, memLimitBytes: 512_000_000, cpuPercent: 2.3, owner: "acme"),
                ContainerStat(name: "worker", memUsedBytes: 340_000_000, memLimitBytes: 512_000_000, cpuPercent: 6.7, owner: "globex"),
                ContainerStat(
                    name: "supabase_analytics_acme_dashboard_realtime_replica_worker", memUsedBytes: 1_300_000_000,
                    memLimitBytes: 2_000_000_000, cpuPercent: 12.4, owner: "acme"),
            ]),
        "backup": snapshot(
            loadFactor: 0.3,
            users: [UserRAM(user: "acme", rssBytes: 300_000_000)],
            containers: [],
            dockerAvailable: false),
        "staging": snapshot(
            loadFactor: 0.5,
            users: [UserRAM(user: "globex", rssBytes: 480_000_000)],
            containers: [
                ContainerStat(name: "dashboard", memUsedBytes: 180_000_000, memLimitBytes: 512_000_000, cpuPercent: 2.4, owner: "globex"),
            ]),
    ]

    static let statsMachines: [StatsMachine] = [
        StatsMachine(name: "main", firstAddress: "203.0.113.10"),
        StatsMachine(name: "backup", firstAddress: "203.0.113.11"),
        StatsMachine(name: "staging", firstAddress: "203.0.113.12"),
    ]

    /// `DEVMACHINE_DEMO_STATS_MACHINE=backup` opens Stats on that demo
    /// machine, to look at a machine without Docker. Main by default, so the
    /// website's screenshots stay as they are.
    static func statsMachine(from environment: [String: String]) -> String {
        let asked = environment["DEVMACHINE_DEMO_STATS_MACHINE"] ?? ""
        return statsMachines.contains { $0.name == asked } ? asked : "main"
    }

    /// How old each demo snapshot reads, so Home shows a fresh card, an
    /// older one, and a stale one.
    static let statsAges: [String: TimeInterval] = ["main": 40, "backup": 180, "staging": 720]

    static let statsErrors: [String: String] = [
        "staging": "ssh: connect to host 203.0.113.12 port 22: Operation timed out",
    ]

    // MARK: Health

    static let machineHealth: [MachineHealth] = [
        MachineHealth(
            id: "main", machineName: "main", isSelf: true,
            checks: [
                DoctorCheck(name: "disk space", status: .pass, detail: "42% used"),
                DoctorCheck(name: "docker", status: .pass, detail: "running"),
                DoctorCheck(name: "ssh aliases", status: .pass, detail: "up to date"),
                DoctorCheck(name: "certificate renewal", status: .warn, detail: "renews in 6 days, next run in 4h"),
                DoctorCheck(name: "caddy", status: .pass, detail: "reachable"),
            ]),
        MachineHealth(
            id: "backup", machineName: "backup", isSelf: false,
            checks: [
                DoctorCheck(name: "disk space", status: .pass, detail: "18% used"),
                DoctorCheck(name: "backup job", status: .pass, detail: "last run 3h ago"),
            ]),
    ]

    // MARK: Recent custom commands

    static let paletteRecents = ["go.stats", "machine.main.subdomains", "settings.appearance"]

    static let recentCommands: [String: [String]] = [
        "acme-devmachine": ["npm run dev", "htop", "claude --model opus"],
        "globex-devmachine": ["npm run dev", "bin/rails server", "tail -f log/development.log"],
    ]

    // MARK: Settings

    /// A landscape drawn in code, never the bundled or a downloaded photo: those
    /// show real people and places that the website has no rights to reuse.
    static let settings = AppSettings(
        opsRepoPath: operatorPath,
        hostAlias: "devmachine",
        publicIP: machineAddress,
        baseDomain: "example.com",
        wallpaper: .gradient(name: "peaks"),
        enabledHarnesses: [.claude, .codex, .pi, .antigravity, .opencode, .kimi, .cline],
        localSessionProgram: .harness(.claude),
        remoteSessionProgram: .harness(.claude),
        workspaceSessionPrograms: [
            "globex-devmachine": .custom("npm run dev"),
            "initech-devmachine": .harness(.codex),
        ],
        operatorProgram: .harness(.claude))

    /// The CLIs the demo Mac has. Antigravity and Cline are left out, so
    /// Settings shows a harness that only starts on a remote workspace.
    static let executableLocator: any ExecutableLocating = DemoExecutableLocator(
        installed: ["claude", "codex", "pi", "opencode", "kimi"])

    // MARK: Harness usage

    static var usageProviders: [any HarnessUsageProvider] {
        usageProviders(failing: failingUsageHarnesses(from: ProcessInfo.processInfo.environment))
    }

    /// `DEVMACHINE_DEMO_USAGE_ERROR=codex` makes that harness's usage fail as
    /// if it were signed out, to look at the error state. Off by default, so
    /// the website's screenshots keep their numbers.
    static func failingUsageHarnesses(from environment: [String: String]) -> Set<String> {
        let raw = environment["DEVMACHINE_DEMO_USAGE_ERROR"] ?? ""
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func usageProviders(failing: Set<String>) -> [any HarnessUsageProvider] {
        usageSamples.map { sample in
            DemoUsageProvider(
                harnessID: sample.harnessID, snapshot: sample.snapshot,
                failure: failing.contains(sample.harnessID) ? DemoUsageError.notSignedIn : nil)
        }
    }

    private static let usageSamples: [DemoUsageProvider] = [
        DemoUsageProvider(
            harnessID: "claude",
            snapshot: HarnessUsageSnapshot(
                planName: "Max",
                blocks: [
                    UsageBlock(kind: .session, label: "Session", percent: 62, resets: "in 2h 10m"),
                    UsageBlock(kind: .weeklyAll, label: "Weekly (all models)", percent: 41, resets: "Mon"),
                    UsageBlock(kind: .weeklyModel, label: "Weekly (Opus)", percent: 28, resets: "Mon"),
                ],
                stats: UsageStats(
                    dailyTotals: [
                        DayTokens(date: "2026-09-23", tokens: 540_000),
                        DayTokens(date: "2026-09-24", tokens: 910_000),
                        DayTokens(date: "2026-09-25", tokens: 760_000),
                        DayTokens(date: "2026-09-26", tokens: 310_000),
                        DayTokens(date: "2026-09-27", tokens: 820_000),
                        DayTokens(date: "2026-09-28", tokens: 1_140_000),
                        DayTokens(date: "2026-09-29", tokens: 640_000),
                    ],
                    modelTotals: [
                        ModelTokens(model: "claude-sonnet", tokens: 3_420_000),
                        ModelTokens(model: "claude-opus", tokens: 1_150_000),
                        ModelTokens(model: "claude-haiku", tokens: 550_000),
                    ],
                    todayTokens: 640_000, mostUsedModel: "claude-sonnet"),
                summaryMetrics: [UsageSummaryMetric(id: "today", label: "Today", value: "640K tokens")])),
        DemoUsageProvider(
            harnessID: "codex",
            snapshot: HarnessUsageSnapshot(
                planName: "Plus",
                blocks: [
                    UsageBlock(kind: .session, label: "Session", percent: 35, resets: "in 4h"),
                    UsageBlock(kind: .weeklyAll, label: "Weekly", percent: 52, resets: "Mon"),
                ],
                stats: nil,
                summaryMetrics: [UsageSummaryMetric(id: "today", label: "Today", value: "410K tokens")])),
    ]

    // MARK: Session context (the context panel)

    /// The context panel's demo data: one fixed answer for every session, so
    /// a Claude session's panel always has a plan, pull requests and links to
    /// show, the way a real mid-task session would.
    static let contextState = ContextState(
        cwd: "/Users/alice/dev/acme-app",
        isClaude: true,
        updatedAt: ISO8601DateFormatter().string(from: Date()),
        plan: ContextState.Plan(
            title: "Fix double-charge on gateway timeout",
            source: "session",
            done: 2,
            total: 4,
            items: [
                ContextState.Plan.Item(text: "Reproduce the double-charge with a fake gateway", state: "done"),
                ContextState.Plan.Item(text: "Add an idempotency key to ChargeService", state: "done"),
                ContextState.Plan.Item(text: "Cover the timeout-then-retry path with a test", state: "active"),
                ContextState.Plan.Item(text: "Update CHANGELOG", state: "pending"),
            ]),
        prs: [
            ContextState.PR(
                number: 412, repo: "acme/api", title: "Fix double-charge on gateway timeout",
                url: "https://github.com/acme/api/pull/412", ci: "success", review: "approved", state: "open",
                threads: 2, lastSeen: nil),
            ContextState.PR(
                number: 3, repo: "acme/api", title: "Bump the webhook signing key rotation to 30 days",
                url: "https://github.com/acme/api/pull/3", ci: "failure", review: "changes_requested", state: "open",
                threads: 1, lastSeen: nil),
            ContextState.PR(
                number: 415, repo: "acme/api", title: "Log the idempotency key on every retry",
                url: "https://github.com/acme/api/pull/415", ci: "pending", review: "none", state: "draft",
                threads: nil, lastSeen: nil),
            ContextState.PR(
                number: 405, repo: "acme/api", title: "Retry the gateway call once on timeout",
                url: "https://github.com/acme/api/pull/405", ci: "success", review: "approved", state: "merged",
                threads: nil, lastSeen: nil),
            ContextState.PR(
                number: 401, repo: "acme/web", title: "Disable the pay button while a charge runs",
                url: "https://github.com/acme/web/pull/401", ci: "none", review: "none", state: "closed",
                threads: nil, lastSeen: nil),
        ],
        links: [
            ContextState.Link(url: "https://github.com/acme/api/issues/398", label: "double-charge on retry", kind: "issue"),
            ContextState.Link(url: "https://acme.example.com/docs/payments", label: "payments runbook", kind: "doc"),
            ContextState.Link(url: "https://github.com/acme/api/pull/405", label: "gateway retry", kind: "pr"),
            ContextState.Link(url: "https://linear.example.com/acme/issue/PAY-212", label: "PAY-212 retries", kind: "linear"),
        ])

    static let operatorContextState = ContextState(
        cwd: operatorPath,
        isClaude: true,
        updatedAt: ISO8601DateFormatter().string(from: Date()),
        plan: ContextState.Plan(
            title: "Add the globex workspace",
            source: "session",
            done: 3,
            total: 4,
            items: [
                ContextState.Plan.Item(text: "Add globex to config.yml", state: "done"),
                ContextState.Plan.Item(text: "Add the claude-code package to globex", state: "done"),
                ContextState.Plan.Item(text: "Sync the machine", state: "done"),
                ContextState.Plan.Item(text: "Open a session in globex", state: "active"),
            ]),
        prs: [],
        links: [
            ContextState.Link(url: "https://example.com/docs/workspaces", label: "workspaces guide", kind: "doc"),
        ])

    /// The Operator gets its own answer, since it works on the setup rather
    /// than on a project; every other target shares one mid-task session.
    static func contextState(for target: CommandTarget) -> ContextState? {
        if case let .local(session, _) = target, session == Workspace.operatorSession {
            return operatorContextState
        }
        return contextState
    }

    // MARK: Context panel shortcuts

    static let skills: [SkillCommand] = [
        SkillCommand(label: "review", command: "/review", systemImage: "checkmark.seal"),
        SkillCommand(label: "test", command: "/test", systemImage: "list.bullet"),
        SkillCommand(label: "plan", command: "/plan", systemImage: "chart.bar"),
        SkillCommand(label: "commit", command: "/commit", systemImage: "text.bubble"),
    ]

    // MARK: Publish-a-port suggestions

    static let publishSuggestions = (
        ports: [
            PortSuggestion(port: 3000, containerName: "web"),
            PortSuggestion(port: 8080, containerName: "api"),
        ],
        domain: domain)
}

/// A `HarnessUsageProvider` that hands back a fixed snapshot — used only in
/// demo mode, in place of `ClaudeUsageProvider`/`CodexUsageProvider`, which
/// read the owner's real usage files.
struct DemoUsageProvider: HarnessUsageProvider {
    let harnessID: String
    let snapshot: HarnessUsageSnapshot
    var failure: DemoUsageError?

    func fetchSnapshot(previous: HarnessUsageSnapshot?) throws -> HarnessUsageSnapshot {
        if DemoMode.holdsLoading {
            DispatchSemaphore(value: 0).wait()
        }
        if let failure { throw failure }
        return snapshot
    }
}

enum DemoUsageError: Error, LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return """
            account/rateLimits/read failed: {"code":-32600,"message":"Not logged in. Run `codex login` to sign in."}
            """
        }
    }
}

// MARK: Git

extension DemoData {
    static let gitSnapshot = GitSnapshot(
        root: "/home/acme/dev/api-payments",
        branch: "payments-refactor",
        upstream: "origin/payments-refactor",
        ahead: 2,
        dirtyFiles: 1,
        worktrees: [
            GitSnapshot.Worktree(path: "/home/acme/dev/api", head: "4e1f0a2", branch: "main", isMain: true),
            GitSnapshot.Worktree(
                path: "/home/acme/dev/api-docs", head: "4e1f0a2", branch: "docs-typos", isMain: false),
            GitSnapshot.Worktree(
                path: "/home/acme/dev/api-payments", head: "9b7c3d1", branch: "payments-refactor", isMain: false),
            GitSnapshot.Worktree(
                path: "/home/acme/dev/api-spike", head: "71aa0c9", branch: "spike-cache", isMain: false,
                isLocked: true, lockReason: "on an external disk"),
            GitSnapshot.Worktree(
                path: "/home/acme/dev/api-webhooks", head: "c20d8e4", branch: "webhooks-retry", isMain: false),
        ],
        commits: [
            GitSnapshot.Commit(
                sha: "9b7c3d1", subject: "Retry the charge once on a gateway timeout", author: "alice",
                age: "12 minutes ago", refs: ["payments-refactor"]),
            GitSnapshot.Commit(
                sha: "5d2e8f0", subject: "Extract the gateway client", author: "alice", age: "2 hours ago",
                refs: []),
            GitSnapshot.Commit(
                sha: "4e1f0a2", subject: "Fix typos in the webhooks guide", author: "bob", age: "yesterday",
                refs: ["origin/main", "main"]),
        ])

    static let worktreeChecks: [WorktreeCheck] = [
        WorktreeCheck(
            path: "/home/acme/dev/api-docs", branch: "docs-typos", upstream: nil, uncommittedChanges: 0,
            unpushedCommits: nil, unmergedCommits: 0, mainBranch: "main", isLocked: false, lockReason: nil),
        WorktreeCheck(
            path: "/home/acme/dev/api-spike", branch: "spike-cache", upstream: nil, uncommittedChanges: 0,
            unpushedCommits: nil, unmergedCommits: 2, mainBranch: "main", isLocked: true,
            lockReason: "on an external disk"),
        WorktreeCheck(
            path: "/home/acme/dev/api-webhooks", branch: "webhooks-retry", upstream: "origin/webhooks-retry",
            uncommittedChanges: 3, unpushedCommits: 1, unmergedCommits: 4, mainBranch: "main",
            isLocked: false, lockReason: nil),
    ]

    /// A worktree a root container wrote into, for the sheet's ownership section.
    static let foreignWorktreeCheck = WorktreeCheck(
        path: "/home/acme/dev/api/.worktrees/search-index", branch: "search-index", upstream: nil,
        uncommittedChanges: 0, unpushedCommits: nil, unmergedCommits: 0, mainBranch: "main",
        isLocked: false, lockReason: nil,
        foreignFiles: ForeignFiles(
            user: "acme",
            paths: [
                "/home/acme/dev/api/.worktrees/search-index/.data/postgres",
                "/home/acme/dev/api/.worktrees/search-index/.data/postgres/base",
                "/home/acme/dev/api/.worktrees/search-index/.data/postgres/pg_wal",
            ],
            count: 214))
}

struct DemoExecutableLocator: ExecutableLocating {
    let installed: Set<String>

    func executable(named name: String) -> URL? {
        installed.contains(name) ? URL(fileURLWithPath: "/opt/homebrew/bin").appendingPathComponent(name) : nil
    }
}
