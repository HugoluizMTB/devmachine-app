import AppKit
import SwiftUI
import DevmachineCore

/// Invented chats for demo mode, seeded into the real stores, and the
/// `DEVMACHINE_DEMO_WALK=chats` screens drawn from the real views.
@MainActor
enum DemoChats {
    static let workspaces = ["main", "acme-api", "blog"]
    static let selectedID = "rebuild"

    static func seed(_ store: ChatStore, now: Date = Date(), calendar: Calendar = .current) {
        store.workspaces = workspaces
        store.settings = ChatSettings()
        let records = chats(now: now, calendar: calendar)
        var conversations: [String: ChatConversation] = [:]
        for record in records {
            conversations[record.id] = ChatConversation(record: record, messages: messages(for: record.id))
        }
        conversations[selectedID]?.isStreaming = true
        store.seedDemo(
            records: records + askRecords(now: now), conversations: conversations,
            config: ChatCLIConfig(defaultWorkspace: "main"))
    }

    private static func chats(now: Date, calendar: Calendar) -> [ChatRecord] {
        let today = calendar.startOfDay(for: now)
        func todayAt(_ hoursAgo: Double) -> Date { now.addingTimeInterval(-hoursAgo * 3600) }
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .hour, value: 12, to: calendar.date(byAdding: .day, value: -days, to: today)!)!
        }
        let rows: [(String, String, String, HarnessID, Date)] = [
            (selectedID, "How sessions are rebuilt", "main", .claude, now.addingTimeInterval(-20)),
            ("caddy", "Caddy reload without downtime", "main", .claude, todayAt(2)),
            ("flaky", "Why the webhook test is flaky", "acme-api", .codex, todayAt(4)),
            ("regex", "Regex for ISO dates", "main", .claude, daysAgo(1)),
            ("rss", "Add an RSS feed to the blog", "blog", .claude, daysAgo(1).addingTimeInterval(-3600)),
            ("pg", "Postgres index for the events table", "acme-api", .codex, daysAgo(3)),
            ("tmux", "tmux copy mode keys", "main", .claude, daysAgo(5)),
            ("dns", "TTL for the new subdomain", "main", .claude, daysAgo(6)),
        ]
        return rows.map { id, title, workspace, harness, date in
            ChatRecord(
                id: id, title: title, harness: harness, workspace: workspace, folder: ChatSettings.defaultFolder,
                harnessSessionID: "demo-\(id)", createdAt: date, updatedAt: date, mcp: id == selectedID)
        }
    }

    private static func messages(for id: String) -> [ChatMessage] {
        switch id {
        case selectedID:
            return [
                ChatMessage(role: .user, text: "How does the CLI rebuild the session list after a sweep? Point me at the code."),
                ChatMessage(role: .assistant, text: rebuildAnswer, tools: [
                    ChatTool(name: "Read", summary: "internal/sessions/build.go"),
                    ChatTool(name: "Grep", summary: "\"func Rebuild\" in 3 files"),
                ], denied: [ChatTool(name: "Bash", summary: "go test ./internal/sessions/...")]),
                ChatMessage(role: .user, text: "And what happens when a workspace is paused?"),
                ChatMessage(
                    role: .assistant,
                    text: "A paused workspace is skipped before any ssh starts: `Rebuild` filters it out in "
                        + "`activeAliases`, and its rows stay in the list greyed out with the time it was paused. "
                        + "Nothing is read from it until",
                    tools: [ChatTool(name: "Read", summary: "internal/sessions/pause.go")]),
            ]
        case "caddy":
            return [
                ChatMessage(role: .user, text: "How do I reload Caddy without dropping connections?"),
                ChatMessage(role: .assistant, text: "Use `caddy reload`: it swaps the config in place and keeps open connections."),
            ]
        default:
            return []
        }
    }

    private static let rebuildAnswer = """
        It starts from `tmux list-sessions` on each workspace and merges that with what the last sweep saw, \
        so a session that vanished for one tick does not blink out of the list.

        - `Rebuild` reads every alias in parallel, capped at 4 at a time.
        - A failed alias keeps its **last good list** and is marked stale.
        - Rows are sorted by last activity, then by name.

        ```go
        func Rebuild(ctx context.Context, aliases []string) ([]Session, error) {
            sem := make(chan struct{}, 4)
            for _, alias := range aliases {
                sem <- struct{}{}
                go readAlias(ctx, alias, sem)
            }
            return merge(previous, fresh), nil
        }
        ```
        """

    // MARK: - Ask

    static let askAnswer = "The retry after a gateway timeout charged twice. It added an idempotency key to "
        + "`gateway.charge`, so the second call reuses the first charge instead of making a new one."
    static let askFollowUpAnswer = "Yes: `testTimeoutThenRetryChargesOnce` fakes the timeout and checks one charge."

    /// The selected chat, answered to the end: the site loop scrolls through
    /// it instead of watching it stream.
    static func finishedRebuild(_ store: ChatStore) -> ChatConversation {
        var conversation = store.conversation(selectedID)
        conversation.isStreaming = false
        if let last = conversation.messages.indices.last {
            conversation.messages[last].text += " the workspace is resumed."
        }
        return conversation
    }

    static let askClaudeSession = "claude — payments refactor"
    static let askCodexSession = "codex — landing page"

    private static func askRecords(now: Date) -> [ChatRecord] {
        [
            ChatRecord(
                id: "ask-claude", title: "why did it change ChargeService?", harness: .claude, workspace: "acme",
                createdAt: now.addingTimeInterval(-300), updatedAt: now.addingTimeInterval(-240),
                kind: ChatRecord.askKind, session: askClaudeSession, mode: "transcript", excerpts: 4),
            ChatRecord(
                id: "ask-codex", title: "why did it change Hero.tsx?", harness: .codex, workspace: "acme",
                createdAt: now.addingTimeInterval(-300), updatedAt: now.addingTimeInterval(-240),
                kind: ChatRecord.askKind, session: askCodexSession, mode: "transcript", excerpts: 3),
        ]
    }

    static func askConversations(_ store: ChatStore) {
        guard let claude = store.record("ask-claude"), let codex = store.record("ask-codex") else { return }
        store.seedDemoConversation("ask-claude", ChatConversation(record: claude, messages: [
            ChatMessage(role: .user, text: "why did it change ChargeService?"),
            ChatMessage(
                role: .assistant,
                text: "The retry after a gateway timeout charged twice. It added an idempotency key to "
                    + "`gateway.charge`, so the second call reuses the first charge instead of making a new one.\n\n"
                    + "[Sources/Payments/ChargeService.swift:42](https://example.com)"),
        ]))
        store.seedDemoConversation("ask-codex", ChatConversation(record: codex, messages: [
            ChatMessage(role: .user, text: "why did it change Hero.tsx?"),
            ChatMessage(
                role: .assistant,
                text: "The hero video loaded on first paint and slowed the page. It added `preload=\"none\"` and "
                    + "`loading=\"lazy\"`, so the video loads only when it scrolls into view.\n\n"
                    + "[src/components/Hero.tsx:12](https://example.com)"),
        ]))
    }

    // MARK: - Walk

    static let screens: [DemoSnapshots.Screen] = [
        .init(id: "chat-main", fileName: "01-chat-main.png", settleNanoseconds: 900_000_000),
        .init(id: "chat-new", fileName: "02-chat-new.png", settleNanoseconds: 500_000_000),
        .init(id: "chat-picker-harness", fileName: "03-chat-picker-harness.png", settleNanoseconds: 500_000_000),
        .init(id: "chat-picker-workspace", fileName: "04-chat-picker-workspace.png", settleNanoseconds: 500_000_000),
        .init(id: "code-toggle", fileName: "05-code-toggle.png", settleNanoseconds: 900_000_000),
        .init(id: "quick-panel", fileName: "06-quick-panel.png", settleNanoseconds: 400_000_000),
        .init(id: "quick-panel-answer", fileName: "07-quick-panel-answer.png", settleNanoseconds: 600_000_000),
        .init(id: "quick-panel-continue", fileName: "08-quick-panel-continue.png", settleNanoseconds: 400_000_000),
        .init(id: "menubar-chats", fileName: "09-menubar-chats.png", settleNanoseconds: 500_000_000),
        .init(id: "palette-chats", fileName: "10-palette-chats.png", settleNanoseconds: 600_000_000),
        .init(id: "context-ask-claude", fileName: "11-context-ask-claude.png", settleNanoseconds: 1_200_000_000),
        .init(id: "context-ask-codex", fileName: "12-context-ask-codex.png", settleNanoseconds: 1_200_000_000),
        .init(id: "chat-error-logged-out", fileName: "13-chat-error-logged-out.png", settleNanoseconds: 600_000_000),
        .init(id: "settings-chats", fileName: "14-settings-chats.png", settleNanoseconds: 500_000_000),
        .init(id: "chat-mode-menu", fileName: "15-chat-mode-menu.png", settleNanoseconds: 500_000_000),
        .init(id: "schedule-mode", fileName: "16-schedule-mode.png", settleNanoseconds: 900_000_000),
        .init(id: "sidebar-collapsed", fileName: "17-sidebar-collapsed.png", settleNanoseconds: 900_000_000),
        .init(id: "chats-collapsed", fileName: "18-chats-collapsed.png", settleNanoseconds: 700_000_000),
        .init(id: "schedule-collapsed", fileName: "19-schedule-collapsed.png", settleNanoseconds: 900_000_000),
        .init(id: "home-open", fileName: "20-home-open.png", settleNanoseconds: 900_000_000),
        .init(id: "home-collapsed", fileName: "21-home-collapsed.png", settleNanoseconds: 900_000_000),
        .init(id: "chat-connecting", fileName: "22-chat-connecting.png", settleNanoseconds: 600_000_000),
    ]

    static let panelScreens: Set<String> = ["quick-panel", "quick-panel-answer", "quick-panel-continue", "menubar-chats"]

    static func handles(_ id: String) -> Bool {
        screens.contains { $0.id == id }
    }

    static func prepare(_ id: String, model: AppModel, store: ChatStore = .shared) async {
        DemoContextOverride.shared.value = nil
        DemoData.transcriptOverride = [:]
        seed(store)
        store.openPicker = nil
        model.sidebarCollapsed = false
        switch id {
        case "schedule-mode":
            #if DEBUG
            DemoScheduled.seed(ScheduledStore.shared)
            ScheduledStore.shared.selectedID = DemoScheduled.briefingID
            #endif
            model.showPage(.scheduled)
        case "home-open":
            model.goHome()
        case "home-collapsed":
            model.goHome()
            model.sidebarCollapsed = true
        case "chats-collapsed":
            model.showChats(select: selectedID, store: store)
            model.sidebarCollapsed = true
        case "schedule-collapsed":
            #if DEBUG
            DemoScheduled.seed(ScheduledStore.shared)
            ScheduledStore.shared.selectedID = DemoScheduled.briefingID
            #endif
            model.showPage(.scheduled)
            model.sidebarCollapsed = true
        case "sidebar-collapsed":
            model.clickSession(SessionRef(alias: "globex-devmachine", name: "claude"))
            model.contextTab = .context
            model.sidebarCollapsed = true
        case "chat-main":
            model.showChats(select: selectedID, store: store)
        case "chat-new":
            model.showNewChat(store: store)
        case "chat-picker-harness", "chat-picker-workspace":
            model.showNewChat(store: store)
            store.openPicker = id == "chat-picker-harness" ? .harness : .workspace
        case "chat-error-logged-out":
            store.seedDemoConversation(selectedID, ChatConversation(
                record: store.record(selectedID),
                messages: [ChatMessage(role: .user, text: "what does the retry loop in build.go do?")],
                failure: ChatFailure(
                    kind: .harnessLoggedOut,
                    message: "Invalid API key · Please run /login")))
            model.showChats(select: selectedID, store: store)
        case "chat-connecting":
            store.seedDemoConversation(selectedID, ChatConversation(
                record: store.record(selectedID),
                messages: [ChatMessage(role: .user, text: "what does the retry loop in build.go do?")],
                isStreaming: true, status: "Connecting to main…"))
            model.showChats(select: selectedID, store: store)
        case "chat-mode-menu":
            model.showChats(select: selectedID, store: store)
            model.showsModeMenu = true
        case "palette-chats":
            model.showChats(select: selectedID, store: store)
            DemoSnapshots.paletteInitialQuery = "chat"
            model.showCommandPalette = true
        case "settings-chats":
            DemoSnapshots.setupInitialSection = .chats
            model.openSettings(.chats)
        case "code-toggle":
            model.clickSession(SessionRef(alias: "globex-devmachine", name: "claude"))
            model.contextTab = .context
        case "context-ask-claude", "context-ask-codex":
            let codex = id == "context-ask-codex"
            askConversations(store)
            DemoContextOverride.shared.value = askContext(claude: !codex)
            if !codex { DemoData.transcriptOverride = [askTranscriptKind: askTranscript(working: false)] }
            model.contextCollapsed = false
            model.contextWidth = DMPaneWidth.context.ideal
            model.clickSession(SessionRef(alias: "acme-devmachine", name: codex ? askCodexSession : askClaudeSession))
            model.contextTab = .context
        default:
            break
        }
    }

    static func reset(_ store: ChatStore = .shared) {
        DemoContextOverride.shared.value = nil
        DemoData.transcriptOverride = [:]
        store.openPicker = nil
        AppModel.shared?.sidebarCollapsed = false
    }

    static func askContext(claude: Bool) -> ContextState {
        let base = DemoData.contextState
        let stamp = ISO8601DateFormatter().string(from: Date())
        if !claude {
            return ContextState(
                cwd: "/home/acme/web", isClaude: false, updatedAt: stamp,
                plan: ContextState.Plan(
                    title: "Speed up the landing page", source: "session", done: 2, total: 3,
                    items: [
                        ContextState.Plan.Item(text: "Measure the landing page load", state: "done"),
                        ContextState.Plan.Item(text: "Lazy-load the hero video", state: "done"),
                        ContextState.Plan.Item(text: "Compress the hero poster image", state: "active"),
                    ]),
                prs: [],
                links: [
                    ContextState.Link(url: "https://github.com/acme/web/pull/89", label: "Lazy-load the hero video",
                                      kind: "pr"),
                    ContextState.Link(url: "https://acme.example.com", label: "acme.example.com", kind: "site"),
                ])
        }
        return ContextState(
            cwd: base.cwd, isClaude: true, updatedAt: stamp,
            plan: base.plan.map { plan in
                ContextState.Plan(
                    title: plan.title, source: plan.source, done: 2, total: 3, items: Array(plan.items.prefix(3)))
            },
            prs: [], links: Array(base.links.prefix(2)))
    }
}

extension DemoChats {
    static let quickQuestion = "how do I list tmux sessions on another socket?"

    static func standaloneView(_ id: String, environment: DemoSnapshots.Environment) -> NSView {
        let store = ChatStore.shared
        if id == "menubar-chats" {
            return DemoSnapshots.standaloneView(
                DemoSnapshots.prPanel(environment, height: 820).frame(width: 776),
                fittingSize: NSSize(width: 776, height: 820), fixedHeight: 820)
        }
        let model = QuickChatModel(store: store)
        switch id {
        case "quick-panel-answer":
            let record = ChatRecord(
                id: "quick", title: quickQuestion, harness: .claude, workspace: "main", createdAt: Date(),
                updatedAt: Date())
            store.seedDemoConversation("quick", ChatConversation(
                record: record,
                messages: [
                    ChatMessage(role: .user, text: quickQuestion),
                    ChatMessage(role: .assistant, text: quickAnswerText),
                ],
                isStreaming: true))
            model.seedDemo(chatKey: "quick", question: quickQuestion)
        case "quick-panel-continue":
            model.seedDemo(chatKey: nil, question: nil, showsChooser: true)
        default:
            break
        }
        let height: CGFloat = switch id {
        case "quick-panel-answer": 560
        case "quick-panel-continue": 440
        default: 300
        }
        return DemoSnapshots.standaloneView(
            QuickChatBackdrop(height: height) { QuickChatCard(model: model) },
            fittingSize: NSSize(width: 900, height: height), autosize: false)
    }

    static let quickAnswerText = """
        Pass the socket with `-L` (a name) or `-S` (a path) before the command:

        ```sh
        tmux -L work list-sessions
        tmux -S /tmp/tmux-1000/shared ls
        ```

        Every server has its own socket, so `ls` alone only shows the default one. To see which sockets exist, list
        """
}

/// A desktop-like wash behind the quick panel, for the demo frames only.
struct QuickChatBackdrop<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: () -> Content
    @Environment(\.dmMetrics) private var m

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(hex: 0x2A3442), Color(hex: 0x3B2F3F), Color(hex: 0x1B2230)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            content().padding(.top, m.pt(70))
        }
        .frame(width: m.pt(900), height: m.pt(height))
        .environment(\.colorScheme, .dark)
    }
}

extension DemoChats {
    static let askTranscriptKind = TerminalKind.remote(alias: "acme-devmachine", session: askClaudeSession)

    /// The payments refactor session's screen, long enough to fill the pane,
    /// so the terminal beside the Ask section shows output, not empty rows.
    static func askTranscript(working: Bool) -> String {
        let esc = "\u{1B}["
        let cyan = esc + "36m", green = esc + "32m", red = esc + "31m", yellow = esc + "33m"
        let dim = esc + "2m", bold = esc + "1m", plain = esc + "0m"
        var lines = [
            "\(bold)\(cyan)● Claude Code\(plain) — payments refactor",
            "",
            "\(cyan)⏺\(plain) Read Sources/Payments/ChargeService.swift (212 lines)",
            "\(cyan)⏺\(plain) Read Sources/Payments/GatewayClient.swift (148 lines)",
            "\(cyan)⏺\(plain) Grep \"retry\" in Sources/Payments — 9 matches",
            "",
            "The retry loop in ChargeService.charge(_:) calls gateway.charge again after a",
            "timeout. The gateway may have taken the first charge, so a slow reply turns",
            "into two charges on the customer's card.",
            "",
            "\(bold)Todo\(plain)",
            "  \(green)✔\(plain) Reproduce the double-charge with a fake gateway",
            "  \(green)✔\(plain) Add an idempotency key to ChargeService",
            "  \(yellow)→\(plain) Cover the timeout-then-retry path with a test",
            "",
            "\(cyan)⏺\(plain) Update Sources/Payments/ChargeService.swift",
            "  \(dim)40\(plain)   func charge(_ order: Order) async throws -> Receipt {",
            "  \(dim)41\(plain)       for attempt in 1...maxAttempts {",
            "  \(dim)42\(plain) \(red)-         let receipt = try await gateway.charge(order)\(plain)",
            "  \(dim)42\(plain) \(green)+         let receipt = try await gateway.charge(\(plain)",
            "  \(dim)43\(plain) \(green)+             order, idempotencyKey: order.id.uuidString)\(plain)",
            "  \(dim)44\(plain)           if receipt.isSettled { return receipt }",
            "  \(dim)45\(plain)       }",
            "",
            "\(cyan)⏺\(plain) Update Tests/PaymentsTests/ChargeServiceTests.swift",
            "  \(green)+   func testTimeoutThenRetryChargesOnce() async throws {\(plain)",
            "  \(green)+       let gateway = FakeGateway(firstReply: .timeout)\(plain)",
            "  \(green)+       let service = ChargeService(gateway: gateway)\(plain)",
            "  \(green)+       _ = try await service.charge(.sample)\(plain)",
            "  \(green)+       XCTAssertEqual(gateway.charges.count, 1)\(plain)",
            "  \(green)+   }\(plain)",
            "",
            "\(cyan)⏺\(plain) Bash swift test --filter ChargeService",
            "  Building for debugging...",
            "  Test Suite 'ChargeServiceTests' started",
            "  Test Case 'testChargeSucceedsOnFirstTry' passed (0.012 seconds)",
            "  Test Case 'testDeclinedCardThrows' passed (0.009 seconds)",
            "  Test Case 'testTimeoutThenRetryChargesOnce' passed (0.031 seconds)",
            "  \(green)Test Suite 'ChargeServiceTests' passed: 6 tests, 0 failures\(plain)",
            "",
            "The retry now sends the same idempotency key, so the gateway returns the",
            "first charge instead of taking a second one.",
            "",
            "\(cyan)⏺\(plain) Read Sources/Payments/RefundService.swift (96 lines)",
            "RefundService has the same retry shape; checking it next.",
        ]
        if working {
            lines += [
                "",
                "\(cyan)⏺\(plain) Update Sources/Payments/RefundService.swift",
                "  \(dim)31\(plain) \(green)+         idempotencyKey: refund.id.uuidString)\(plain)",
                "\(cyan)⏺\(plain) Bash swift test --filter RefundService",
                "  \(green)Test Suite 'RefundServiceTests' passed: 4 tests, 0 failures\(plain)",
            ]
        }
        lines.append("\(cyan)❯\(plain)")
        return lines.joined(separator: "\n")
    }
}
