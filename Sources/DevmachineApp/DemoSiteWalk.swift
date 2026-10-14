#if DEBUG
import SwiftUI
import AppKit
import DevmachineCore

/// Debug builds only. The website's short loops, for
/// `DEVMACHINE_DEMO_WALK=site`: five scenes, each a run of frames written to
/// `<scene>/NNN.png` with a `frames.ffconcat` beside them that says how long
/// each frame stays on screen. `scripts/site_demo_videos.sh` turns each
/// scene into a video. Every frame is the real window in a state the app can
/// reach, drawn from demo data; nothing runs.
@MainActor
enum DemoSiteWalk {
    struct Frame: Equatable {
        let step: Step
        /// Seconds the frame stays on screen in the video.
        let hold: Double
    }

    enum Step: Equatable {
        case sidebar, busy, attention, sessionGrid
        case cli(Int)
        case context(Int)
        case publishedApps, publishing, published, shareSheet, shareLink, chat, guestReply
        case home, homeWide
    }

    struct Scene: Equatable {
        let id: String
        let frames: [Frame]

        var seconds: Double { frames.reduce(0) { $0 + $1.hold } }
    }

    static let windowSize = NSSize(width: 1600, height: 1000)

    static let scenes: [Scene] = [
        Scene(id: "sessions", frames: [
            Frame(step: .sidebar, hold: 1.6),
            Frame(step: .busy, hold: 1.8),
            Frame(step: .attention, hold: 2.0),
            Frame(step: .sessionGrid, hold: 3.2),
        ]),
        Scene(id: "cli", frames: cliTranscripts.indices.map { index in
            Frame(step: .cli(index), hold: index == cliTranscripts.count - 1 ? 3.2 : 0.9)
        }),
        Scene(id: "context", frames: contextStates.indices.map { index in
            Frame(step: .context(index), hold: index == contextStates.count - 1 ? 2.6 : 1.3)
        }),
        Scene(id: "publish", frames: [
            Frame(step: .publishedApps, hold: 1.2),
            Frame(step: .publishing, hold: 1.0),
            Frame(step: .published, hold: 1.3),
            Frame(step: .shareSheet, hold: 1.3),
            Frame(step: .shareLink, hold: 1.5),
            Frame(step: .chat, hold: 1.0),
            Frame(step: .guestReply, hold: 2.4),
        ]),
        Scene(id: "home", frames: [
            Frame(step: .home, hold: 3.6),
            Frame(step: .homeWide, hold: 3.6),
        ]),
    ]

    static let screens: [DemoSnapshots.Screen] = scenes.flatMap { scene in
        scene.frames.indices.map { index in
            DemoSnapshots.Screen(
                id: screenID(scene: scene.id, index: index),
                fileName: "\(scene.id)/\(frameName(index))",
                settleNanoseconds: 350_000_000)
        }
    }

    static func handles(_ id: String) -> Bool { id.hasPrefix("site-") }

    static func screenID(scene: String, index: Int) -> String {
        "site-\(scene)-\(String(format: "%03d", index + 1))"
    }

    static func frameName(_ index: Int) -> String {
        String(format: "%03d.png", index + 1)
    }

    static func frame(for id: String) -> Frame? {
        for scene in scenes {
            for index in scene.frames.indices where screenID(scene: scene.id, index: index) == id {
                return scene.frames[index]
            }
        }
        return nil
    }

    /// ffmpeg's concat list: each frame with its time on screen. The last
    /// frame is named once more, so it starts no earlier than its hold ends;
    /// the video script cuts the scene at `seconds`.
    static func ffconcat(_ scene: Scene) -> String {
        var lines = ["ffconcat version 1.0"]
        for (index, frame) in scene.frames.enumerated() {
            lines.append("file '\(frameName(index))'")
            lines.append("duration \(String(format: "%.2f", frame.hold))")
        }
        if !scene.frames.isEmpty {
            lines.append("file '\(frameName(scene.frames.count - 1))'")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func writeTimings(into directory: URL) {
        for scene in scenes {
            let folder = directory.appendingPathComponent(scene.id, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? Data(ffconcat(scene).utf8).write(to: folder.appendingPathComponent("frames.ffconcat"))
        }
    }

    static func reset(_ model: AppModel) {
        DemoData.transcriptOverride = [:]
        DemoContextOverride.shared.value = nil
        SessionShareStore.shared.seedDemo([])
        model.contextCollapsed = false
        model.sidebarCollapsed = false
        model.contextWidth = DMPaneWidth.context.ideal
    }

    /// With the Chat tab the panel has five tabs, and at its ideal width the
    /// first title wraps.
    static let chatPanelWidth: CGFloat = 340

    // MARK: - Steps

    static func prepare(_ id: String, environment: DemoSnapshots.Environment) async {
        guard let frame = frame(for: id) else { return }
        let model = environment.model
        switch frame.step {
        case .sidebar:
            reset(model)
            model.sessionsByAlias = sessions(busy: false, attention: false)
            model.contextCollapsed = true
            model.clickSession(SessionRef(alias: "globex-devmachine", name: "claude"))
        case .busy:
            model.sessionsByAlias = sessions(busy: true, attention: false)
        case .attention:
            model.sessionsByAlias = sessions(busy: true, attention: true)
        case .sessionGrid:
            model.goHome()
            model.openSessionGrid(acme)
        case let .cli(index):
            if index == 0 {
                model.goHome()
                model.contextCollapsed = true
                model.selection = DemoSnapshots.operatorSelection
            }
            DemoData.transcriptOverride = [operatorKind: cliTranscripts[index]]
        case let .context(index):
            if index == 0 {
                DemoData.transcriptOverride = [:]
                model.goHome()
                model.contextCollapsed = false
                model.contextTab = .context
                model.clickSession(contextSession)
            }
            DemoContextOverride.shared.value = contextStates[index]
            DemoData.transcriptOverride = [contextKind: contextTranscripts[index]]
            model.context.retry()
        case .publishedApps:
            DemoContextOverride.shared.value = nil
            DemoData.transcriptOverride = [:]
            DemoSnapshots.subdomainsInitialTab = .sites
            model.showPage(.subdomains)
            try? await Task.sleep(nanoseconds: 400_000_000)
            showSites(environment.caddyStore, extra: nil)
        case .publishing:
            showSites(environment.caddyStore, extra: .pending)
        case .published:
            showSites(environment.caddyStore, extra: .published)
        case .shareSheet:
            model.goHome()
            model.contextWidth = chatPanelWidth
            model.contextCollapsed = false
            model.contextTab = .context
            model.clickSession(shareSession)
        case .shareLink:
            break
        case .chat:
            SessionShareStore.shared.seedDemo([shareRecord])
            SessionChatStore.shared.receive(ownerMessage, share: shareRecord.id)
            model.contextTab = .chat
        case .guestReply:
            SessionChatStore.shared.receive(guestMessage, share: shareRecord.id)
        case .home:
            SessionShareStore.shared.seedDemo([])
            model.goHome()
            model.sidebarCollapsed = false
            try? await Task.sleep(nanoseconds: 300_000_000)
            relayHome(model)
        case .homeWide:
            model.sidebarCollapsed = true
        }
    }

    /// Home's board was written for the window the app opened with, before
    /// the walk sized it; written again for this window, it lays the cards
    /// out the way a person with this window first sees them.
    private static func relayHome(_ model: AppModel) {
        let controller = HomeBoardController.shared
        try? FileManager.default.removeItem(at: BoardStore.homeFileURL(configDirectory: DemoMode.boardsFolder))
        controller.canvasWidth = Int(windowSize.width - model.sidebarWidth - ResizeHandle.width)
        controller.reload()
    }

    /// A sheet drawn over the window for this frame, as macOS shows it.
    static func sheet(for id: String) -> AnyView? {
        switch frame(for: id)?.step {
        case .shareSheet:
            return AnyView(ShareSessionSheet(
                request: SessionShareRequest(alias: acme, workspace: "acme", session: shareSession.name),
                onCancel: {}, onShare: { _, _, _ in }))
        case .shareLink:
            return AnyView(ShareOutcomeSheet(
                outcome: .started(shareRecord, password: "otter-lamp-42"), onStop: { _ in }, onClose: {}))
        default:
            return nil
        }
    }

    // MARK: - Sessions

    private static let acme = "acme-devmachine"

    private static let indicators: [String: SessionIndicators] = [
        "claude — payments refactor": SessionIndicators(branch: "fix/double-charge", ageSeconds: 7_400),
        "codex — landing page": SessionIndicators(branch: "feat/lazy-hero", ageSeconds: 2_600),
        "api — tests": SessionIndicators(branch: "main", ageSeconds: 11_000),
        "web — dev server": SessionIndicators(branch: "main", ageSeconds: 90_000),
        "dashboard — tests": SessionIndicators(branch: "main", ageSeconds: 18_000),
        "claude": SessionIndicators(branch: "feat/export-csv", ageSeconds: 1_500),
        "codex": SessionIndicators(branch: "chore/deps", ageSeconds: 180_000),
        "pi — docs": SessionIndicators(branch: "docs/setup", ageSeconds: 5_000),
        "agy — search": SessionIndicators(branch: "feat/search", ageSeconds: 30_000),
    ]

    static func sessions(busy: Bool, attention: Bool) -> [String: [TmuxSession]] {
        DemoData.sessionsByAlias.mapValues { list in
            list.map { session in
                var marked = session
                var shown = indicators[session.name] ?? SessionIndicators(ageSeconds: 4_000)
                shown.busy = busy && session.name == "claude — payments refactor"
                shown.attention = attention && session.name == "codex — landing page"
                marked.indicators = shown
                return marked
            }
        }
    }

    // MARK: - CLI

    static let operatorKind = TerminalKind.local(
        session: Workspace.operatorSession, path: DemoData.operatorPath)

    private static let dim = "\u{1B}[2m"
    private static let bold = "\u{1B}[1m"
    private static let green = "\u{1B}[32m"
    private static let yellow = "\u{1B}[33m"
    private static let cyan = "\u{1B}[36m"
    private static let plain = "\u{1B}[0m"

    private static func command(_ text: String) -> String { "\(cyan)$\(plain) \(bold)\(text)\(plain)" }

    /// Each step adds what the CLI prints next. The wording is the CLI's
    /// own: `machines add`, `packages add` and `sync`, with Ansible's output
    /// in between.
    static let cliSteps: [[String]] = [
        [command("devmachine machines add --name main --address 203.0.113.10 --key ~/.ssh/id_ed25519")],
        [
            "",
            "main at 203.0.113.10 presented ssh-ed25519 host key SHA256:Zm9yZXhhbXBsZW9ubHk.",
            "the key ~/.ssh/id_ed25519 already logs in as root@203.0.113.10, so no password is needed.",
        ],
        [
            "turning password login off...",
            "password login is off; the key is the only way in.",
            "installing Ansible...",
        ],
        [
            "",
            "added main to /Users/alice/.config/devmachine/config.yml",
            "",
            "Next: `devmachine doctor --machine main`, then `devmachine sync --machine main`.",
            "",
        ],
        [command("devmachine packages add claude-code --workspace acme"), "added claude-code to workspace acme", ""],
        [
            command("devmachine sync --machine main"),
            "",
            "PLAY [main] ********************************************************",
            "",
            "TASK [Gathering Facts] *********************************************",
            "\(green)ok: [main]\(plain)",
        ],
        [
            "",
            "TASK [workspace : Create the account] ******************************",
            "\(yellow)changed: [main]\(plain)",
            "",
            "TASK [claude-code : Install Claude Code] ***************************",
            "\(yellow)changed: [main]\(plain)",
        ],
        [
            "",
            "PLAY RECAP *********************************************************",
            "main     : \(green)ok=86\(plain)  \(yellow)changed=12\(plain)  unreachable=0  failed=0",
            "",
            "main: ok=86 changed=12 failed=0",
            "",
            "Reach a workspace:",
            "  devmachine ssh acme (or `devmachine mosh acme`) reaches it from here",
            "  ssh acme-devmachine reaches it from any terminal or editor (VS Code Remote-SSH, Zed, the macOS app)",
            "",
            "\(cyan)$\(plain) ",
        ],
    ]

    static let cliTranscripts: [String] = cliSteps.indices.map { index in
        cliSteps[...index].flatMap { $0 }.joined(separator: "\n")
    }

    // MARK: - Context

    static let contextSession = SessionRef(alias: "globex-devmachine", name: "claude")

    private static let planTexts = [
        "Reproduce the double-charge with a fake gateway",
        "Add an idempotency key to ChargeService",
        "Cover the timeout-then-retry path with a test",
        "Update CHANGELOG",
    ]

    private struct ContextStep {
        let done: Int
        let agent: String?
        let ci: String
    }

    private static let contextSteps: [ContextStep] = [
        ContextStep(done: 2, agent: nil, ci: "pending"),
        ContextStep(done: 2, agent: "running", ci: "pending"),
        ContextStep(done: 2, agent: "done", ci: "pending"),
        ContextStep(done: 3, agent: "done", ci: "success"),
        ContextStep(done: 4, agent: "done", ci: "success"),
    ]

    static let contextStates: [ContextState] = contextSteps.map { context(done: $0.done, agent: $0.agent, ci: $0.ci) }

    static let contextKind = TerminalKind.remote(alias: contextSession.alias, session: contextSession.name)

    private static let todoTexts = [
        "Reproduce with a fake gateway", "Add an idempotency key", "Cover the retry path in a test", "Update CHANGELOG",
    ]

    /// The session's own screen keeps pace with the panel: the same to-do
    /// list, the sub-agent's call, the test run and the last edit.
    static let contextTranscripts: [String] = contextSteps.map { step in
        var lines = [
            "\(bold)\(cyan)● Claude Code\(plain) — payments refactor",
            "",
            "\(dim)Reading ChargeService.swift\(plain)",
            "\(dim)Reading RefundService.swift\(plain)",
            "",
            "Found the retry loop that double-",
            "charges on a gateway timeout.",
            "",
            "\(bold)Todo\(plain)",
        ]
        for (index, text) in todoTexts.enumerated() {
            if index < step.done {
                lines.append("  \(green)✔\(plain) \(text)")
            } else if index == step.done {
                lines.append("  \(yellow)→\(plain) \(text)")
            } else {
                lines.append("  \(dim)○ \(text)\(plain)")
            }
        }
        if let agent = step.agent {
            lines += ["", "\(cyan)⏺\(plain) Task(Explore: find every retry caller)"]
            lines.append(agent == "done"
                ? "  \(dim)⎿ 3 callers, all through ChargeService\(plain)"
                : "  \(dim)⎿ Searching…\(plain)")
        }
        if step.done >= 3 {
            lines += [
                "", "\(dim)$\(plain) swift test --filter Charge",
                "\(green)Test Suite passed\(plain) at 09:14:02.", "\(green)  7 tests, 0 failures\(plain)",
            ]
        }
        if step.done >= 4 {
            lines += ["", "\(dim)~ CHANGELOG.md\(plain)", "\(green)+ Charges keep one idempotency key\(plain)"]
        }
        lines += ["\(cyan)❯\(plain)"]
        return lines.joined(separator: "\n")
    }

    private static func context(done: Int, agent: String?, ci: String) -> ContextState {
        let items = planTexts.enumerated().map { index, text in
            ContextState.Plan.Item(
                text: text, state: index < done ? "done" : (index == done ? "active" : "pending"))
        }
        let base = DemoData.contextState
        let prs = base.prs.map { pr in
            pr.number == 415
                ? ContextState.PR(
                    number: pr.number, repo: pr.repo, title: pr.title, url: pr.url, ci: ci,
                    review: ci == "success" ? "approved" : pr.review, state: ci == "success" ? "open" : pr.state,
                    threads: pr.threads, lastSeen: pr.lastSeen)
                : pr
        }
        return ContextState(
            cwd: base.cwd, isClaude: true, updatedAt: base.updatedAt,
            plan: ContextState.Plan(
                title: "Fix double-charge on gateway timeout", source: "session",
                done: min(done, items.count), total: items.count, items: items),
            prs: prs, links: base.links,
            agents: agent.map { [ContextState.Agent(label: "Explore: find every retry caller", status: $0)] } ?? [])
    }

    // MARK: - Publish and share

    private static let shopRow = { (status: ExposedSite.Status) in
        SubdomainRow(
            site: ExposedSite(host: "shop.acme.example.com", port: 5173, workspace: "acme", status: status),
            resolvedWorkspace: "acme", containerName: status == .published ? "shop" : nil)
    }

    private static func showSites(_ caddy: CaddyStore, extra: ExposedSite.Status?) {
        var states = DemoData.subdomainStates
        if let extra {
            states["main"] = MachineSitesState(rows: DemoData.subdomainRows + [shopRow(extra)], hasLoaded: true)
        }
        caddy.show(
            machines: DemoData.subdomainMachines, states: states, selected: DemoData.subdomainSelectedMachine)
    }

    static let shareSession = SessionRef(alias: "acme-devmachine", name: "claude — payments refactor")

    static let shareRecord = SessionShareRecord(
        id: "wvx3januvgyj", workspace: "acme", alias: "acme-devmachine", session: shareSession.name,
        name: shareSession.name, mode: .read, url: "https://share-acme.example.com/s/wvx3januvgyj/",
        createdAt: Date(), expiresAt: Date().addingTimeInterval(3_600))

    private static let ownerMessage = SessionChatMessage(
        id: "site-1", ts: Date(), from: "alice", role: "owner",
        text: "Watch the retry test: it should pass now.")

    private static let guestMessage = SessionChatMessage(
        id: "site-2", ts: Date().addingTimeInterval(20), from: "bob", role: "guest",
        text: "Green here too. Ship it!")
}
#endif
