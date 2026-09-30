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
        ],
    ]

    static let localSessions: [LocalSession] = [
        LocalSession(name: Workspace.operatorSession, path: "/Users/alice/dev/ops"),
        LocalSession(name: "claude", path: "/Users/alice/dev/acme-app"),
        LocalSession(name: "codex", path: "/Users/alice/dev/globex-dashboard"),
    ]

    // MARK: Terminal transcripts

    // Lines are kept short (well under 45 columns): a stacked grid cell is
    // narrow, and a terminal wraps mid-word rather than mid-sentence — a long
    // line here reads fine alone but breaks ugly once four panes share a
    // window.
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

    \u{1B}[2m--- a/ChargeService.swift\u{1B}[0m
    \u{1B}[2m+++ b/ChargeService.swift\u{1B}[0m
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
    \u{1B}[2m$\u{1B}[0m devmachine workspaces list
    NAME      STATUS
    acme      online
    globex    online
    initech   online
    umbrella  online

    \u{1B}[36m$\u{1B}[0m
    """

    /// One static transcript per demo session, chosen by what the session's
    /// name and kind suggest — this is cosmetic only, so a name that does not
    /// match anything falls back to a plain shell.
    static func terminalTranscript(for kind: TerminalKind) -> String {
        // A live pane's text always arrives through a PTY, which turns a
        // program's bare "\n" into "\r\n" — a carriage return as well as a
        // line feed. `feed(text:)` skips the PTY, so a Swift multi-line
        // string's plain "\n" only moves the cursor down a row, at whatever
        // column it was already at, leaving every line after the first
        // starting mid-row instead of at the left edge.
        //
        // The leading "clear screen, cursor home" sequence is what a real
        // shell sends on start too, so the pane opens at the top-left the
        // same way a live session does.
        "\u{1B}[2J\u{1B}[H" + rawTranscript(for: kind).replacingOccurrences(of: "\n", with: "\r\n")
    }

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
            if lowered.contains("claude") { return claudeTranscript }
            if lowered.contains("codex") { return codexTranscript }
            return operatorTranscript
        }
    }

    // MARK: Subdomains

    static let domain = "acme.example.com"

    static let subdomainRows: [SubdomainRow] = [
        SubdomainRow(
            site: ExposedSite(host: "app.acme.example.com", port: 3000, workspace: "acme", status: .published),
            resolvedWorkspace: "acme", containerName: "web"),
        SubdomainRow(
            site: ExposedSite(host: "api.acme.example.com", port: 8080, workspace: "acme", status: .published),
            resolvedWorkspace: "acme", containerName: "api"),
        SubdomainRow(
            site: ExposedSite(host: "staging.globex.example.com", port: 4000, workspace: "globex", status: .pending),
            resolvedWorkspace: "globex", containerName: "dashboard"),
    ]

    static let dnsProviders = ["cloudflare", "hostinger"]

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

    // MARK: Stats

    private static func snapshot(loadFactor: Double, users: [UserRAM], containers: [ContainerStat]) -> StatsSnapshot {
        StatsSnapshot(
            collectedAt: ISO8601DateFormatter().string(from: Date()),
            memory: .init(totalBytes: 16 * 1_000_000_000, usedBytes: Int64(Double(9_600_000_000) * loadFactor), availableBytes: 6_400_000_000),
            swap: .init(totalBytes: 2 * 1_000_000_000, usedBytes: 128_000_000),
            disk: .init(path: "/", usedBytes: 84_000_000_000, availableBytes: 116_000_000_000, usedPercent: 42),
            load: .init(load1: 1.2 * loadFactor, load5: 0.9 * loadFactor, load15: 0.7 * loadFactor),
            docker: .init(available: true, containers: containers),
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
            ]),
        "backup": snapshot(
            loadFactor: 0.3,
            users: [UserRAM(user: "acme", rssBytes: 300_000_000)],
            containers: [
                ContainerStat(name: "restic", memUsedBytes: 64_000_000, memLimitBytes: 256_000_000, cpuPercent: 1.1, owner: nil),
            ]),
        "staging": snapshot(
            loadFactor: 0.5,
            users: [UserRAM(user: "globex", rssBytes: 480_000_000)],
            containers: [
                ContainerStat(name: "dashboard", memUsedBytes: 180_000_000, memLimitBytes: 512_000_000, cpuPercent: 2.4, owner: "globex"),
            ]),
    ]

    static let statsMachines: [StatsMachine] = [
        StatsMachine(name: "backup", firstAddress: "203.0.113.11"),
        StatsMachine(name: "staging", firstAddress: "203.0.113.12"),
    ]

    // MARK: Health

    static let machineHealth: [MachineHealth] = [
        MachineHealth(
            id: "main", machineName: "main", isSelf: true,
            checks: [
                DoctorCheck(name: "disk space", status: .pass, detail: "42% used"),
                DoctorCheck(name: "docker", status: .pass, detail: "running"),
                DoctorCheck(name: "ssh aliases", status: .pass, detail: "up to date"),
                DoctorCheck(name: "certificate renewal", status: .warn, detail: "renews in 6 days, next run in 4"),
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

    static let recentCommands: [String: [String]] = [
        "acme-devmachine": ["npm run dev", "htop", "claude --model opus"],
        "globex-devmachine": ["npm run dev", "bin/rails server", "tail -f log/development.log"],
    ]

    // MARK: Settings

    static let settings = AppSettings(
        opsRepoPath: "/Users/alice/dev/ops",
        hostAlias: "devmachine",
        publicIP: machineAddress,
        baseDomain: "example.com",
        enabledHarnesses: [.claude, .codex],
        localSessionProgram: .harness(.claude),
        remoteSessionProgram: .harness(.claude),
        workspaceSessionPrograms: [
            "globex-devmachine": .custom("npm run dev"),
            "initech-devmachine": .harness(.codex),
        ])

    // MARK: Harness usage

    static let usageProviders: [any HarnessUsageProvider] = [
        DemoUsageProvider(
            harnessID: "claude",
            snapshot: HarnessUsageSnapshot(
                planName: "Max",
                blocks: [
                    UsageBlock(kind: .session, label: "Session", percent: 62, resets: "resets in 2h 10m"),
                    UsageBlock(kind: .weeklyAll, label: "Weekly (all models)", percent: 41, resets: "resets Mon"),
                    UsageBlock(kind: .weeklyModel, label: "Weekly (Opus)", percent: 28, resets: "resets Mon"),
                ],
                stats: UsageStats(
                    dailyTotals: [
                        DayTokens(date: "2026-09-27", tokens: 820_000),
                        DayTokens(date: "2026-09-28", tokens: 1_140_000),
                        DayTokens(date: "2026-09-29", tokens: 640_000),
                    ],
                    modelTotals: [
                        ModelTokens(model: "claude-sonnet-5", tokens: 1_900_000),
                        ModelTokens(model: "claude-opus-4", tokens: 700_000),
                    ],
                    todayTokens: 640_000, mostUsedModel: "claude-sonnet-5"),
                summaryMetrics: [UsageSummaryMetric(id: "today", label: "Today", value: "640K tokens")])),
        DemoUsageProvider(
            harnessID: "codex",
            snapshot: HarnessUsageSnapshot(
                planName: "Plus",
                blocks: [
                    UsageBlock(kind: .session, label: "Session", percent: 35, resets: "resets in 4h"),
                    UsageBlock(kind: .weeklyAll, label: "Weekly", percent: 52, resets: "resets Mon"),
                ],
                stats: nil,
                summaryMetrics: [UsageSummaryMetric(id: "session", label: "Session", value: "35%")])),
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
        ],
        links: [
            ContextState.Link(url: "https://github.com/acme/api/issues/398", label: "double-charge on retry", kind: "issue"),
            ContextState.Link(url: "https://acme.example.com/docs/payments", label: "payments runbook", kind: "doc"),
        ])

    /// One `ContextSource.context(for:settings:)` answer, the same for every
    /// target: the panel needs no live process to show something realistic.
    static func contextState(for target: CommandTarget) -> ContextState? {
        contextState
    }

    // MARK: Publish-a-port suggestions

    static let publishSuggestions = QuickPublishSuggestions(
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

    func fetchSnapshot(previous: HarnessUsageSnapshot?) throws -> HarnessUsageSnapshot {
        snapshot
    }
}
