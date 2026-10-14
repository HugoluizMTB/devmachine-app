#if DEBUG
import SwiftUI
import AppKit
import DevmachineCore

/// Debug builds only. The website's short loops, for
/// `DEVMACHINE_DEMO_WALK=site`: five scenes, each a run of frames written to
/// `<scene>/NNN.png` with a `frames.ffconcat` beside them that says how long
/// each frame stays on screen. `scripts/site_demo_videos.sh` turns each
/// scene into a video. Every frame is the real window in a state the app can
/// reach, drawn from demo data; nothing runs. A bitmap capture has no
/// pointer, so the walk draws one: it moves to the control a state comes
/// from, clicks, and stays there.
@MainActor
enum DemoSiteWalk {
    struct Click: Equatable {
        /// A `demoClickTarget` id; `sheet:` ids sit in the sheet drawn over
        /// the window.
        let target: String
        var secondary = false
    }

    struct Frame: Equatable {
        let step: Step
        /// Seconds the frame stays on screen in the video.
        let hold: Double
        var click: Click?
    }

    enum Step: Equatable {
        case sidebar, busy, attention, sessionGrid
        case operatorBefore, cli(Int)
        case contextBefore, context(Int)
        case publishBefore, publishedApps, publishing, published
        case sessionOpen, shareSheet, shareLink, shared, chat, guestReply
        case homeBefore, home, homeWide
    }

    struct Scene: Equatable {
        let id: String
        let frames: [Frame]

        var seconds: Double {
            frames.reduce(0) { $0 + $1.hold + ($1.click == nil ? 0 : DemoPointer.clickSeconds) }
        }
    }

    static let windowSize = NSSize(width: 1600, height: 1000)

    private static let acmeClaude = "session:acme-devmachine/claude — payments refactor"

    static let scenes: [Scene] = [
        Scene(id: "sessions", frames: [
            Frame(step: .sidebar, hold: 1.4),
            Frame(step: .busy, hold: 1.6),
            Frame(step: .attention, hold: 1.8),
            Frame(step: .sessionGrid, hold: 2.8, click: Click(target: "grid:acme-devmachine")),
        ]),
        Scene(id: "cli", frames: [Frame(step: .operatorBefore, hold: 0.8)]
            + cliTranscripts.indices.map { index in
                Frame(
                    step: .cli(index), hold: index == cliTranscripts.count - 1 ? 2.8 : 0.7,
                    click: index == 0 ? Click(target: "local:\(Workspace.operatorSession)") : nil)
            }),
        Scene(id: "context", frames: [Frame(step: .contextBefore, hold: 0.9)]
            + contextStates.indices.map { index in
                Frame(
                    step: .context(index), hold: index == contextStates.count - 1 ? 2.4 : 1.2,
                    click: index == 0 ? Click(target: "session:globex-devmachine/claude") : nil)
            }),
        Scene(id: "publish", frames: [
            Frame(step: .publishBefore, hold: 0.6),
            Frame(step: .publishedApps, hold: 0.7, click: Click(target: "footer:published-apps")),
            Frame(step: .publishing, hold: 0.6),
            Frame(step: .published, hold: 0.7),
            Frame(step: .sessionOpen, hold: 0.5, click: Click(target: acmeClaude)),
            Frame(step: .shareSheet, hold: 0.7, click: Click(target: acmeClaude, secondary: true)),
            Frame(step: .shareLink, hold: 0.9, click: Click(target: "sheet:share")),
            Frame(step: .shared, hold: 0.4, click: Click(target: "sheet:done")),
            Frame(step: .chat, hold: 0.6, click: Click(target: "tab:Chat")),
            Frame(step: .guestReply, hold: 1.3),
        ]),
        Scene(id: "home", frames: [
            Frame(step: .homeBefore, hold: 0.7),
            Frame(step: .home, hold: 2.4, click: Click(target: acmeClaude)),
            Frame(step: .homeWide, hold: 2.8, click: Click(target: "footer:close-sidebar")),
        ]),
    ]

    /// One entry per state, so `DEVMACHINE_DEMO_WALK=site` is a walk like
    /// the others; `run` draws the pointer frames between them.
    static let screens: [DemoSnapshots.Screen] = scenes.flatMap { scene in
        scene.frames.indices.map { index in
            DemoSnapshots.Screen(
                id: "site-\(scene.id)-\(String(format: "%03d", index + 1))",
                fileName: "\(scene.id)/\(frameName(index))",
                settleNanoseconds: 350_000_000)
        }
    }

    static func handles(_ id: String) -> Bool { id.hasPrefix("site-") }

    static func frameName(_ index: Int) -> String {
        String(format: "%03d.png", index + 1)
    }

    /// ffmpeg's concat list: each frame with its time on screen. The last
    /// frame is named once more, so it starts no earlier than its hold ends;
    /// the video script cuts the scene at the sum of the holds.
    static func ffconcat(_ holds: [Double]) -> String {
        var lines = ["ffconcat version 1.0"]
        for (index, hold) in holds.enumerated() {
            lines.append("file '\(frameName(index))'")
            lines.append("duration \(String(format: "%.3f", hold))")
        }
        if !holds.isEmpty {
            lines.append("file '\(frameName(holds.count - 1))'")
        }
        return lines.joined(separator: "\n") + "\n"
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

    // MARK: - Running

    static func run(window: NSWindow, environment: DemoSnapshots.Environment, directory: URL) async {
        environment.model.sidebarCollapsed = false
        relayHome(environment.model)
        try? await Task.sleep(nanoseconds: 300_000_000)
        for scene in scenes {
            let folder = directory.appendingPathComponent(scene.id, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var holds: [Double] = []
            var pointer = CGPoint(x: windowSize.width * 0.62, y: windowSize.height * 0.56)
            var base: NSBitmapImageRep?
            var sheetOrigin = CGPoint.zero
            var scale: CGFloat = 2

            func emit(_ rep: NSBitmapImageRep, hold: Double) {
                DemoSnapshots.writeFramed(rep, scale: scale, to: folder.appendingPathComponent(frameName(holds.count)))
                holds.append(hold)
            }

            for frame in scene.frames {
                if let click = frame.click, point(for: click.target, sheet: sheetOrigin) == nil {
                    FileHandle.standardError.write(Data("site walk: no click target \(click.target)\n".utf8))
                }
                if let click = frame.click, let before = base, let target = point(for: click.target, sheet: sheetOrigin) {
                    for position in DemoPointer.path(from: pointer, to: target) {
                        emit(DemoPointer.draw(on: before, at: position, ring: nil, scale: scale),
                             hold: DemoPointer.moveFrameSeconds)
                    }
                    for ring in DemoPointer.rings {
                        emit(DemoPointer.draw(on: before, at: target, ring: ring, scale: scale),
                             hold: DemoPointer.clickFrameSeconds)
                    }
                    pointer = target
                }
                await prepare(frame.step, environment: environment)
                try? await Task.sleep(nanoseconds: 350_000_000)
                TerminalRegistry.shared.replayDemoTranscripts()
                try? await Task.sleep(nanoseconds: 250_000_000)
                window.displayIfNeeded()
                guard let content = window.contentView, let shot = DemoSnapshots.bitmap(of: content) else { continue }
                scale = CGFloat(shot.pixelsWide) / content.bounds.width
                var state = DemoSnapshots.flattenTransparency(shot)
                if let sheet = sheet(for: frame.step) {
                    let hosting = DemoSnapshots.standaloneView(sheet, fittingSize: NSSize(width: 480, height: 400))
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if let sheetShot = DemoSnapshots.bitmap(of: hosting) {
                        let drawn = DemoSnapshots.drawSheet(sheetShot, over: state, scale: scale)
                        state = drawn.image
                        sheetOrigin = drawn.origin
                    }
                    hosting.window?.orderOut(nil)
                }
                base = state
                emit(DemoPointer.draw(on: state, at: pointer, ring: nil, scale: scale), hold: frame.hold)
            }
            try? Data(ffconcat(holds).utf8).write(to: folder.appendingPathComponent("frames.ffconcat"))
        }
    }

    /// The centre of a control, in the main window's points from the top
    /// left; a control in the sheet is moved by where the sheet was drawn.
    private static func point(for target: String, sheet origin: CGPoint) -> CGPoint? {
        guard let frame = DemoClickTargets.frames[target] else { return nil }
        let offset = target.hasPrefix("sheet:") ? origin : .zero
        return CGPoint(x: frame.midX + offset.x, y: frame.midY + offset.y)
    }

    // MARK: - Steps

    static func prepare(_ step: Step, environment: DemoSnapshots.Environment) async {
        let model = environment.model
        switch step {
        case .sidebar:
            reset(model)
            model.sessionsByAlias = sessions(busy: false, attention: false)
            model.contextCollapsed = true
            model.clickSession(contextSession)
        case .busy:
            model.sessionsByAlias = sessions(busy: true, attention: false)
        case .attention:
            model.sessionsByAlias = sessions(busy: true, attention: true)
        case .sessionGrid:
            model.openSessionGrid(acme)
        case .operatorBefore:
            reset(model)
            model.sessionsByAlias = sessions(busy: true, attention: true)
            model.contextCollapsed = true
            model.goHome()
            model.clickSession(contextSession)
        case let .cli(index):
            if index == 0 { model.selection = DemoSnapshots.operatorSelection }
            DemoData.transcriptOverride = [operatorKind: cliTranscripts[index]]
        case .contextBefore:
            reset(model)
            model.sessionsByAlias = sessions(busy: true, attention: true)
            model.contextTab = .context
            model.goHome()
        case let .context(index):
            DemoContextOverride.shared.value = contextStates[index]
            DemoData.transcriptOverride = [contextKind: contextTranscripts[index]]
            if index == 0 { model.clickSession(contextSession) }
            model.context.retry()
        case .publishBefore:
            reset(model)
            model.sessionsByAlias = sessions(busy: true, attention: true)
            model.contextTab = .context
            model.contextWidth = chatPanelWidth
            model.goHome()
        case .publishedApps:
            DemoSnapshots.subdomainsInitialTab = .sites
            model.showPage(.subdomains)
            try? await Task.sleep(nanoseconds: 400_000_000)
            showSites(environment.caddyStore, extra: nil)
        case .publishing:
            showSites(environment.caddyStore, extra: .pending)
        case .published:
            showSites(environment.caddyStore, extra: .published)
        case .sessionOpen:
            model.clickSession(shareSession)
        case .shareSheet:
            break
        case .shareLink:
            SessionShareStore.shared.seedDemo([shareRecord])
        case .shared:
            SessionChatStore.shared.receive(ownerMessage, share: shareRecord.id)
        case .chat:
            model.contextTab = .chat
        case .guestReply:
            SessionChatStore.shared.receive(guestMessage, share: shareRecord.id)
        case .homeBefore:
            reset(model)
            model.sessionsByAlias = sessions(busy: true, attention: true)
            model.contextTab = .context
            model.goHome()
            model.clickSession(shareSession)
        case .home:
            model.clickSession(shareSession)
        case .homeWide:
            model.sidebarCollapsed = true
        }
    }

    /// Home's board was written for the window the app opened with, before
    /// the walk sized it; written again for this window before the first
    /// scene, every scene that shows Home lays the cards out the way a person
    /// with this window first sees them.
    private static func relayHome(_ model: AppModel) {
        let controller = HomeBoardController.shared
        try? FileManager.default.removeItem(at: BoardStore.homeFileURL(configDirectory: DemoMode.boardsFolder))
        controller.canvasWidth = Int(windowSize.width - model.sidebarWidth - ResizeHandle.width)
        controller.reload()
    }

    /// A sheet drawn over the window for this state, as macOS shows it.
    static func sheet(for step: Step) -> AnyView? {
        switch step {
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
