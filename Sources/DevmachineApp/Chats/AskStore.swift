import Foundation
import DevmachineCore

/// Which ask thread each session shows: the one it started in this run of
/// the app, else its newest ask chat. Clear deletes that thread in the CLI,
/// so it does not come back after a restart.
@MainActor
final class AskStore: ObservableObject {
    static let shared = AskStore()

    @Published private(set) var started: [AskSessionKey: String] = [:]
    /// Sessions cleared in this run: no thread until the next question,
    /// even if an older ask chat is still in the CLI's store.
    @Published private(set) var cleared: Set<AskSessionKey> = []
    /// Why the CLI kept a thread Clear tried to delete.
    @Published private(set) var clearFailures: [AskSessionKey: String] = [:]
    /// What is typed in each session's Ask field.
    @Published var drafts: [AskSessionKey: String] = [:]

    func threadID(for key: AskSessionKey, in store: ChatStore) -> String? {
        if let key = started[key] { return store.current(key) }
        if cleared.contains(key) { return nil }
        return AskThreadPicker.latest(in: store.records, key: key)?.id
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
        cleared.remove(key)
        clearFailures[key] = nil
        return sent
    }

    /// Deletes the session's thread and starts over; a delete the CLI refuses
    /// keeps the thread and its reason. Returns whether it cleared.
    @discardableResult
    func clear(_ key: AskSessionKey, store: ChatStore) async -> Bool {
        let id = threadID(for: key, in: store)
        if let id, store.isAnswering(id) { return false }
        if let id, let failure = await store.delete(id) {
            clearFailures[key] = failure
            return false
        }
        started[key] = nil
        cleared.insert(key)
        clearFailures[key] = nil
        drafts[key] = nil
        return true
    }

    /// The demo starts a session over without the CLI.
    func resetDemo(_ key: AskSessionKey) {
        started[key] = nil
        cleared.insert(key)
        clearFailures[key] = nil
        drafts[key] = nil
    }

    func seedDemoThread(_ key: AskSessionKey, chatID: String?) {
        started[key] = chatID
    }
}
