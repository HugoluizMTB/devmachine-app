import Foundation
import DevmachineCore

/// Which ask thread each session shows. A session's thread is the one it
/// started in this run of the app, else its newest ask chat; reset starts
/// over and hides the older ones.
@MainActor
final class AskStore: ObservableObject {
    static let shared = AskStore()

    @Published private(set) var resets: [AskSessionKey: Date] = [:]
    @Published private(set) var started: [AskSessionKey: String] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func threadID(for key: AskSessionKey, in store: ChatStore) -> String? {
        if let key = started[key] { return store.current(key) }
        return AskThreadPicker.latest(in: store.records, key: key, after: resets[key])?.id
    }

    @discardableResult
    func ask(_ question: String, key: AskSessionKey, mode: AskMode, folder: String?, store: ChatStore) -> String? {
        guard mode.isSupported, let harness = mode.harness else { return nil }
        let thread = threadID(for: key, in: store)
        let chatID = thread.flatMap { $0.hasPrefix(ChatStore.pendingPrefix) ? nil : $0 }
        guard let sent = store.ask(question, key: key, harness: harness, folder: folder, chatID: chatID) else {
            return nil
        }
        started[key] = sent
        return sent
    }

    func reset(_ key: AskSessionKey) {
        resets[key] = now()
        started[key] = nil
    }

    /// "Continue in Chats": the thread joins the chat list and opens there.
    func continueInChats(_ key: AskSessionKey, store: ChatStore, model: AppModel?) async {
        guard let id = threadID(for: key, in: store), !id.hasPrefix(ChatStore.pendingPrefix),
              await store.continueAsk(id) else { return }
        started[key] = nil
        resets[key] = now()
        model?.showChats(select: id, store: store)
    }
}
