import Foundation
import DevmachineCore

struct LocalSessionSnapshot: Equatable, Sendable {
    let sessions: [ZmxSession]
    let harnesses: [String: Set<HarnessID>]
}

protocol SessionSource: Sendable {
    func sessions(for workspace: Workspace, settings: AppSettings) throws -> [TmuxSession]
    func localSessions(settings: AppSettings) throws -> LocalSessionSnapshot
}

/// Keeps today's SSH and local multiplexer transport behind domain snapshots.
struct CommandSessionSource: SessionSource {
    let store: SessionStore
    let localRunner: any CommandRunner
    let zmxPath: String?
    let facade: SessionHarnessFacade

    init(
        store: SessionStore = SessionStore(runner: ProcessRunner()),
        localRunner: any CommandRunner = ProcessRunner(),
        zmxPath: String? = LocalTools.zmxPath(),
        facade: SessionHarnessFacade = SessionHarnessFacade()
    ) {
        self.store = store
        self.localRunner = localRunner
        self.zmxPath = zmxPath
        self.facade = facade
    }

    func sessions(for workspace: Workspace, settings: AppSettings) throws -> [TmuxSession] {
        try store.sessions(for: workspace, processNames: facade.processNames(for: settings))
    }

    func localSessions(settings: AppSettings) throws -> LocalSessionSnapshot {
        guard let zmxPath else { return LocalSessionSnapshot(sessions: [], harnesses: [:]) }
        let listing = (try? localRunner.run(
            executable: zmxPath, args: Zmx.listArguments,
            environment: ["ZMX_DIR": Zmx.socketDirectory()])) ?? ""
        let sessions = ZmxListParser.parse(listing)
        var entries: [ProcessTree.Entry] = []
        if !sessions.isEmpty,
           let processes = try? localRunner.run(
            executable: "/bin/ps", args: ProcessTree.listArguments, environment: nil) {
            entries = ProcessTree.parse(processes)
        }
        return LocalSessionSnapshot(
            sessions: sessions,
            harnesses: facade.detect(sessions: sessions, entries: entries, settings: settings))
    }
}
