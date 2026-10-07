import DevmachineCore
import Foundation

/// Reads `repo` and `branch` for the context sidebar, only while a widget on
/// the board reads them. It probes when the session or folder changes, on
/// each new session-context read (`revision`), and when the Context tab
/// comes back; never on a timer of its own. After a failure the next read
/// retries once; a second failure in a row waits for the tab or a new folder.
@MainActor
final class ContextGitStatusStore: ObservableObject {
    @Published private(set) var status: ContextGitStatus?
    private let run: @Sendable (CommandTarget, String) throws -> String
    private var current: (target: CommandTarget, key: String)?
    private var revision: String?
    private var inFlightKey: String?
    private var failures = 0

    private static let failuresBeforeWaiting = 2

    init(run: @escaping @Sendable (CommandTarget, String) throws -> String = { target, body in
        try HostRunner().runCapturingWithFolderArgument(target, body).stdout
    }) {
        self.run = run
    }

    /// A new session or folder has no answer yet; the context waits for it
    /// rather than hand its widgets an empty branch first.
    var isPending: Bool { current != nil && status == nil }

    func refresh(_ target: CommandTarget?, cwd: String?, revision: String? = nil) {
        guard let target else {
            current = nil
            self.revision = nil
            inFlightKey = nil
            if status != nil { status = nil }
            return
        }
        let key = target.key + "|" + (cwd ?? "")
        if key != current?.key {
            current = (target, key)
            self.revision = revision
            failures = 0
            if status != nil { status = nil }
            probe()
        } else if revision != self.revision {
            self.revision = revision
            if failures < Self.failuresBeforeWaiting { probe() }
        }
    }

    func appeared() {
        failures = 0
        probe()
    }

    private func probe() {
        guard let current, inFlightKey != current.key else { return }
        let key = current.key
        let target = current.target
        inFlightKey = key
        let run = self.run
        Task.detached {
            let result = Result { try run(target, ContextGitProbe.body) }
            await MainActor.run { self.finish(result, key: key) }
        }
    }

    private func finish(_ result: Result<String, Error>, key: String) {
        if inFlightKey == key { inFlightKey = nil }
        guard current?.key == key else { return }
        switch result {
        case let .success(stdout):
            failures = 0
            let parsed = ContextGitProbe.parse(stdout)
            if status != parsed { status = parsed }
        case .failure:
            failures += 1
            if status == nil { status = ContextGitProbe.parse("") }
        }
    }
}
