import SwiftUI
import DevmachineCore

/// ASK in the Context sidebar: a side question about the selected session,
/// answered without typing into it.
struct AskWidgetView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var store = ChatStore.shared
    @ObservedObject private var asks = AskStore.shared
    @ObservedObject private var context: ContextStore
    @Environment(\.dmMetrics) private var m
    @State private var question = ""

    init(context: ContextStore) {
        self.context = context
    }

    private var key: AskSessionKey? { model.askSessionKey }

    private var mode: AskMode {
        let detected = context.state?.harness
            ?? model.selectedSessionHarnessIDs.first { ChatHarness.supported.contains($0) }
            ?? model.selectedSessionHarnessIDs.first
        return AskMode(harness: detected)
    }

    var body: some View {
        if let key {
            section(key)
        } else {
            StackEmptyWidgetHeader()
        }
    }

    private func section(_ key: AskSessionKey) -> some View {
        let threadID = asks.threadID(for: key, in: store)
        let conversation = threadID.map(store.conversation)
        return DMSection(
            contentSpacing: 10,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            label: { DMSectionLabel(text: "ASK") },
            trailing: {
                DMIconButton(systemImage: "arrow.counterclockwise", size: 10, hitSize: DMHitSize.header) {
                    asks.reset(key)
                    question = ""
                }
                .help("Start a new thread")
                .accessibilityLabel("Start a new thread")
                .disabled(threadID == nil)
                StackHeaderControls()
            }
        ) {
            VStack(alignment: .leading, spacing: m.pt(10)) {
                HStack(spacing: m.pt(5)) {
                    if let harness = mode.harness { ChatHarnessGlyph(harness: harness, size: 11) }
                    Text(verbatim: mode.subtitle).font(.dm(10.5)).foregroundStyle(Color.dmMuted)
                }
                if let conversation, let threadID, !conversation.messages.isEmpty || conversation.isStreaming {
                    ChatThreadView(conversation: conversation, fontSize: 12, compact: true) { failure in
                        AnyView(ChatErrorCard(
                            failure: failure, chatID: threadID, harness: mode.harness ?? .claude, place: key.place,
                            compact: true))
                    }
                    if let excerpts = conversation.record?.excerpts, excerpts > 0, !conversation.isStreaming {
                        HStack(spacing: m.pt(4)) {
                            Image(systemName: "text.magnifyingglass").font(.dm(9.5))
                            Text(verbatim: excerpts == 1
                                ? "Based on 1 excerpt from the transcript"
                                : "Based on \(excerpts) excerpts from the transcript")
                                .font(.dm(10.5))
                        }
                        .foregroundStyle(Color.dmMuted)
                    }
                }
                if mode.isSupported {
                    input(key, streaming: conversation?.isStreaming == true, threadID: threadID)
                    HStack {
                        DMButton("Continue in Chats", systemImage: "bubble.left.and.bubble.right", variant: .link,
                                 size: .small) {
                            Task { await asks.continueInChats(key, store: store, model: model) }
                        }
                        .disabled(threadID == nil || threadID?.hasPrefix(ChatStore.pendingPrefix) == true)
                        Spacer()
                        Text(verbatim: "the session is not interrupted").font(.dm(10)).foregroundStyle(Color.dmMuted)
                    }
                }
            }
            .task(id: threadID) { if let threadID { store.loadIfNeeded(threadID) } }
            .task { await store.refresh() }
        }
        .demoClickTarget("context:ask")
    }

    private func input(_ key: AskSessionKey, streaming: Bool, threadID: String?) -> some View {
        HStack(spacing: m.pt(6)) {
            TextField("Ask about this session…", text: $question)
                .textFieldStyle(.plain)
                .accessibilityLabel("Ask about this session")
                .accessibilityHint("Return asks; the session is not interrupted")
                .font(.dm(12))
                .onSubmit { send(key) }
                .onKeyPress(.escape) {
                    guard streaming, let threadID else { return .ignored }
                    store.stop(threadID)
                    return .handled
                }
            ChatSendButton(
                size: 20, enabled: !question.trimmingCharacters(in: .whitespaces).isEmpty, stops: streaming
            ) {
                if streaming, let threadID { store.stop(threadID) } else { send(key) }
            }
            .help(streaming ? "Stop (Esc)" : "Ask (Return)")
        }
        .padding(.leading, m.pt(10))
        .padding(.trailing, m.pt(5))
        .padding(.vertical, m.pt(5))
        .dmSurface(Color.dmSelection, radius: DMRadius.pill, style: .continuous)
    }

    private func send(_ key: AskSessionKey) {
        if asks.ask(question, key: key, mode: mode, folder: model.askSessionFolder, store: store) != nil {
            question = ""
        }
    }
}
