#if DEBUG
import AppKit
import SwiftUI
import DevmachineCore

/// The website's chat loops: the quick panel over a desktop, Chats mode, and
/// Ask beside a session that keeps working. Same rules as the other scenes:
/// every frame is a real view in a state the app reaches, from invented data.
extension DemoSiteWalk {
    static let subscriptionLabel = "Your Claude or Codex login — no API key"

    // MARK: - Quick chat

    static let quickQuestion = "how do I list tmux sessions on another socket?"
    static let quickTyped = typing(quickQuestion, steps: 7)
    static let quickAnswerSteps = 6
    static let quickAnswerFull = DemoChats.quickAnswerText + " them with `ls /tmp/tmux-$(id -u)/`."

    private static let quickLabelPoint = CGPoint(x: 345, y: 110)

    static let quickChatScene: Scene = {
        let open = Label(text: "⌃⌥Space opens it over any app", at: quickLabelPoint)
        let login = Label(text: subscriptionLabel, at: quickLabelPoint)
        var frames: [Frame] = [Frame(step: .quickChat(.empty), hold: 2.0, label: open)]
        for index in quickTyped.indices {
            let hold: Double = index == quickTyped.count - 1 ? 0.6 : 0.14
            frames.append(Frame(step: .quickChat(.typing(index)), hold: hold))
        }
        frames.append(Frame(step: .quickChat(.sent), hold: 0.8, label: login))
        for index in 0..<quickAnswerSteps {
            let hold: Double = index == quickAnswerSteps - 1 ? 1.0 : 0.32
            frames.append(Frame(step: .quickChat(.answer(index)), hold: hold, label: login))
        }
        frames.append(Frame(
            step: .quickChat(.done), hold: 2.0, label: Label(text: "⌘↩ opens it in the app", at: quickLabelPoint)))
        frames.append(Frame(
            step: .quickChat(.inApp), hold: 2.8,
            label: Label(text: "…and it is in Chats, ready to continue", at: CGPoint(x: 700, y: 640))))
        return Scene(id: "quickchat", frames: frames)
    }()

    /// The panel and its backdrop for a quick chat step; nil for a step drawn
    /// in the app's window.
    static func desktopView(for step: Step) -> NSView? {
        guard case let .quickChat(phase) = step, phase != .inApp else { return nil }
        if quickDesktop == nil {
            quickDesktop = DemoSnapshots.standaloneView(
                DemoQuickChatDesktop(model: quickModel), fittingSize: windowSize, autosize: false)
        }
        quickDesktop?.layoutSubtreeIfNeeded()
        return quickDesktop
    }

    private static var quickDesktop: NSView?
    private static let quickModel = QuickChatModel(store: .shared)
    private static let quickID = "quick"

    static func prepareQuickChat(_ phase: QuickPhase, model: AppModel) async {
        let store = ChatStore.shared
        switch phase {
        case .empty:
            reset(model)
            DemoChats.seed(store)
            quickModel.text = ""
            quickModel.seedDemo(chatKey: nil, question: nil)
        case let .typing(index):
            quickModel.text = quickTyped[index]
        case .sent:
            quickModel.text = ""
            store.seedDemoConversation(quickID, ChatConversation(
                record: quickRecord(), messages: [ChatMessage(role: .user, text: quickQuestion)], isStreaming: true))
            quickModel.seedDemo(chatKey: quickID, question: quickQuestion)
        case let .answer(index):
            let text = prefix(of: quickAnswerFull, step: index + 1, of: quickAnswerSteps)
            store.seedDemoConversation(quickID, ChatConversation(
                record: quickRecord(),
                messages: [ChatMessage(role: .user, text: quickQuestion), ChatMessage(role: .assistant, text: text)],
                isStreaming: true))
        case .done:
            store.seedDemoConversation(quickID, ChatConversation(
                record: quickRecord(),
                messages: [
                    ChatMessage(role: .user, text: quickQuestion),
                    ChatMessage(role: .assistant, text: quickAnswerFull),
                ]))
        case .inApp:
            DemoChats.seed(store)
            store.seedDemo(
                records: store.records + [quickRecord()],
                conversations: store.conversations.merging([quickID: ChatConversation(
                    record: quickRecord(),
                    messages: [
                        ChatMessage(role: .user, text: quickQuestion),
                        ChatMessage(role: .assistant, text: quickAnswerFull),
                    ])]) { $1 },
                config: store.config)
            model.contextCollapsed = true
            model.showChats(select: quickID, store: store)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private static func quickRecord() -> ChatRecord {
        let now = Date()
        return ChatRecord(
            id: quickID, title: "tmux sessions on another socket", harness: .claude, workspace: "main",
            folder: ChatSettings.defaultFolder, createdAt: now, updatedAt: now)
    }

    // MARK: - Chats

    private static let chatLabel = Label(text: "Claude or Codex, with code you can copy", at: CGPoint(x: 560, y: 120))

    static let chatsScene = Scene(id: "chats", frames: [
        Frame(step: .chatsTour(0), hold: 1.2),
        Frame(step: .chatsTour(1), hold: 1.4, pointer: .click(Spot(target: "sidebar:mode")),
              label: Label(text: "Code, Chats and Schedule", near: "menu:mode-chats")),
        Frame(step: .chatsTour(2), hold: 1.8, pointer: .click(Spot(target: "menu:mode-chats")),
              label: chatLabel),
        Frame(step: .chatsTour(2), hold: 1.8, pointer: .hover(Spot(target: "chat:copy")), label: chatLabel),
        Frame(step: .chatsTour(3), hold: 1.2, pointer: .click(Spot(target: "chats:new"))),
        Frame(step: .chatsTour(4), hold: 2.4, pointer: .click(Spot(target: "chat:harness")),
              label: Label(text: subscriptionLabel, at: CGPoint(x: 640, y: 740))),
        Frame(step: .chatsTour(5), hold: 2.0, pointer: .click(Spot(target: "chat:workspace"))),
        Frame(step: .chatsTour(6), hold: 2.6, pointer: .hover(Spot(target: "chat:readonly")),
              label: Label(text: "It reads your files, never changes them", near: "chat:readonly", below: true)),
    ])

    static func prepareChatsTour(_ index: Int, model: AppModel) async {
        let store = ChatStore.shared
        switch index {
        case 0:
            reset(model)
            DemoChats.seed(store)
            store.seedDemoConversation(DemoChats.selectedID, DemoChats.finishedRebuild(store))
            model.sessionsByAlias = sessions(busy: true, attention: true)
            model.contextCollapsed = true
            model.goHome()
            model.clickSession(contextSession)
            try? await Task.sleep(nanoseconds: 300_000_000)
        case 1:
            model.showsModeMenu = true
        case 2:
            model.showChats(select: DemoChats.selectedID, store: store)
        case 3:
            store.startNewChat()
        case 4:
            store.openPicker = .harness
        case 5:
            store.openPicker = .workspace
        default:
            store.openPicker = nil
        }
    }

    // MARK: - Ask

    static let askKey = AskSessionKey(place: .workspace("acme"), session: contextSession.name)
    private static let askQuestion = "why did it change ChargeService?"
    private static let askFollowUp = "is there a test for the retry?"
    static let askTyped = typing(askQuestion, steps: 5)
    static let followTyped = typing(askFollowUp, steps: 5)
    static let askAnswerSteps = 4

    static let askScene: Scene = {
        let zoom = "context:ask"
        let asking = Label(text: "Ask about the session, beside it", near: zoom)
        let reading = Label(text: "From its transcript, your login, no API key", near: zoom)
        var frames = [
            Frame(step: .ask(.start), hold: 1.2),
            Frame(step: .ask(.start), hold: 0.4, zoom: zoom),
        ]
        frames += askTyped.indices.map { index in
            Frame(step: .ask(.typing(index)), hold: index == askTyped.count - 1 ? 0.7 : 0.14,
                  pointer: index == 0 ? .click(Spot(target: "ask:input")) : nil, label: asking, zoom: zoom)
        }
        frames += (0...askAnswerSteps).map { index in
            Frame(step: .ask(.answer(index)), hold: index == askAnswerSteps ? 2.2 : 0.32,
                  pointer: index == 1 ? .hover(Spot(target: "ask:clear")) : nil, label: reading, zoom: zoom)
        }
        frames.append(Frame(
            step: .ask(.sessionWorks), hold: 2.4,
            label: Label(text: "The session keeps working beside it", at: CGPoint(x: 300, y: 380))))
        frames += followTyped.indices.map { index in
            Frame(step: .ask(.followTyping(index)), hold: index == followTyped.count - 1 ? 0.5 : 0.14, zoom: zoom)
        }
        frames += (0...askAnswerSteps).map { index in
            Frame(step: .ask(.followAnswer(index)), hold: index == askAnswerSteps ? 2.0 : 0.32, zoom: zoom)
        }
        frames.append(Frame(
            step: .ask(.cleared), hold: 2.0, pointer: .click(Spot(target: "ask:clear")),
            label: Label(text: "Clear starts a new thread", near: zoom), zoom: zoom))
        return Scene(id: "ask", frames: frames)
    }()

    private static let askID = "ask-live"

    private static var askSceneContext: ContextState {
        let full = DemoChats.askContext(claude: true)
        return ContextState(
            cwd: full.cwd, isClaude: full.isClaude, updatedAt: full.updatedAt,
            plan: full.plan.map { plan in
                ContextState.Plan(
                    title: plan.title, source: plan.source, done: 1, total: 2, items: Array(plan.items.suffix(2)))
            },
            prs: [], links: Array(full.links.prefix(1)))
    }

    static func prepareAsk(_ phase: AskPhase, model: AppModel) async {
        let store = ChatStore.shared
        let asks = AskStore.shared
        switch phase {
        case .start:
            reset(model)
            DemoChats.seed(store)
            DemoContextOverride.shared.value = askSceneContext
            DemoData.transcriptOverride = [contextKind: DemoChats.askTranscript(working: false)]
            model.sessionsByAlias = sessions(busy: true, attention: true)
            model.contextTab = .context
            model.goHome()
            model.clickSession(contextSession)
            asks.reset(askKey)
            try? await Task.sleep(nanoseconds: 700_000_000)
            model.context.retry()
        case let .typing(index):
            asks.drafts[askKey] = askTyped[index]
        case let .answer(index):
            asks.drafts[askKey] = nil
            asks.seedDemoThread(askKey, chatID: askID)
            store.seedDemoConversation(askID, askConversation(
                answers: [prefix(of: DemoChats.askAnswer, step: index, of: askAnswerSteps)],
                streaming: index < askAnswerSteps))
        case .sessionWorks:
            DemoData.transcriptOverride = [contextKind: DemoChats.askTranscript(working: true)]
        case let .followTyping(index):
            asks.drafts[askKey] = followTyped[index]
        case let .followAnswer(index):
            asks.drafts[askKey] = nil
            store.seedDemoConversation(askID, askConversation(
                answers: [DemoChats.askAnswer, prefix(of: DemoChats.askFollowUpAnswer, step: index, of: askAnswerSteps)],
                streaming: index < askAnswerSteps, followUp: true))
        case .cleared:
            asks.reset(askKey)
        }
    }

    private static func askConversation(answers: [String], streaming: Bool, followUp: Bool = false) -> ChatConversation {
        let now = Date()
        let record = ChatRecord(
            id: askID, title: askQuestion, harness: .claude, workspace: "acme", createdAt: now, updatedAt: now,
            kind: ChatRecord.askKind, session: contextSession.name, mode: "transcript", excerpts: 4)
        var messages = [ChatMessage(role: .user, text: askQuestion)]
        if let first = answers.first, !first.isEmpty || !followUp { messages.append(ChatMessage(role: .assistant, text: first)) }
        if followUp {
            messages.append(ChatMessage(role: .user, text: askFollowUp))
            if answers.count > 1, !answers[1].isEmpty { messages.append(ChatMessage(role: .assistant, text: answers[1])) }
        }
        if messages.last?.role == .assistant, messages.last?.text.isEmpty == true { messages.removeLast() }
        return ChatConversation(record: record, messages: messages, isStreaming: streaming)
    }

    // MARK: - Text

    /// The question as it is typed, a few characters a frame.
    static func typing(_ text: String, steps: Int) -> [String] {
        (1...steps).map { prefix(of: text, step: $0, of: steps) }
    }

    /// The first `step` of `steps` parts of `text`, cut at a word.
    static func prefix(of text: String, step: Int, of steps: Int) -> String {
        guard step < steps else { return text }
        guard step > 0 else { return "" }
        let cut = text.count * step / steps
        let head = String(text.prefix(cut))
        guard let space = head.lastIndex(of: " ") else { return head }
        return String(head[..<space])
    }
}

/// The quick panel over a desktop, for the site's quick chat loop.
struct DemoQuickChatDesktop: View {
    @ObservedObject var model: QuickChatModel
    @Environment(\.dmMetrics) private var m

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(hex: 0x2A3442), Color(hex: 0x3B2F3F), Color(hex: 0x1B2230)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            QuickChatCard(model: model)
                .scaleEffect(1.35, anchor: .top)
                .padding(.top, 170)
        }
        .frame(width: DemoSiteWalk.windowSize.width, height: DemoSiteWalk.windowSize.height)
        .environment(\.colorScheme, .dark)
    }
}
#endif
