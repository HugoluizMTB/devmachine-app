import Foundation
import DevmachineCore

struct LocalSessionSnapshot: Equatable, Sendable {
    let sessions: [ZmxSession]
    let harnesses: [String: Set<HarnessID>]
    var indicators: [String: SessionIndicators] = [:]
}

protocol SessionListSource: Sendable {
    func sessions(for workspace: Workspace, settings: AppSettings) throws -> [TmuxSession]
    func sessions(
        for workspaces: [Workspace], settings: AppSettings
    ) -> [String: Result<[TmuxSession], any Error>]
    func localSessions(settings: AppSettings) throws -> LocalSessionSnapshot
}

extension SessionListSource {
    /// Keyed by workspace alias. A source that can ask every workspace in one
    /// call overrides this.
    func sessions(
        for workspaces: [Workspace], settings: AppSettings
    ) -> [String: Result<[TmuxSession], any Error>] {
        var results: [String: Result<[TmuxSession], any Error>] = [:]
        for workspace in workspaces {
            results[workspace.alias] = Result { try sessions(for: workspace, settings: settings) }
        }
        return results
    }
}

/// Keeps today's SSH and local multiplexer transport behind domain snapshots.
struct CommandSessionSource: SessionListSource {
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
        try store.sessions(for: workspace, processNames: facade.processNames)
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
        let ages = sessions.isEmpty ? [:] : ElapsedTime.parse(
            (try? localRunner.run(
                executable: "/bin/ps", args: ElapsedTime.psArguments(sessions.map(\.pid)),
                environment: nil)) ?? "")
        var branches: [String: String?] = [:]
        for directory in Set(sessions.compactMap(\.directory)) {
            branches[directory] = branch(in: directory)
        }
        let indicators = Dictionary(
            sessions.map { session in
                (session.name, SessionIndicators(
                    path: session.directory,
                    branch: session.directory.flatMap { branches[$0] ?? nil },
                    ageSeconds: ages[session.pid]))
            },
            uniquingKeysWith: { first, _ in first })
        return LocalSessionSnapshot(
            sessions: sessions,
            harnesses: facade.detect(sessions: sessions, entries: entries),
            indicators: indicators)
    }

    private func branch(in directory: String) -> String? {
        guard let name = GitHead.branch(fromAbbrevRef: (try? localRunner.run(
            executable: "/usr/bin/git", args: GitHead.abbrevRefArguments(directory),
            environment: nil)) ?? "")
        else { return nil }
        guard name == "HEAD" else { return name }
        return GitHead.branch(fromAbbrevRef: (try? localRunner.run(
            executable: "/usr/bin/git", args: GitHead.shortSHAArguments(directory),
            environment: nil)) ?? "")
    }
}
