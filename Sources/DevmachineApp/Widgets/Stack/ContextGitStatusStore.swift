import DevmachineCore
import Foundation

/// When the git probe may run. A new session or folder, or the Context tab
/// coming back, probes at once; a new context read (every 5 s poll) only
/// once 30 s have passed since the last probe, failed or not, so a widget
/// showing the branch never costs an ssh round trip per poll.
enum GitProbeThrottle {
    enum Reason {
        case newTarget, appeared, newRead
    }

    static let interval: TimeInterval = 30

    static func allows(_ reason: Reason, lastProbe: Date?, now: Date) -> Bool {
        switch reason {
        case .newTarget, .appeared: return true
        case .newRead: return lastProbe.map { now.timeIntervalSince($0) >= interval } ?? true
        }
    }
}

/// Reads `repo` and `branch` for the context sidebar, only while a widget on
/// the board reads them, when `GitProbeThrottle` allows. Never on a timer
/// of its own: a new read is the session-context poll's (`revision`).
@MainActor
final class ContextGitStatusStore: ObservableObject {
    @Published private(set) var status: ContextGitStatus?
    private let run: @Sendable (CommandTarget, String) throws -> String
    private let now: () -> Date
    private var current: (target: CommandTarget, key: String)?
    private var revision: String?
    private var inFlightKey: String?
    private var lastProbe: Date?

    init(
        run: @escaping @Sendable (CommandTarget, String) throws -> String = { target, body in
            try HostRunner().runCapturingWithFolderArgument(target, body).stdout
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.run = run
        self.now = now
    }

    static func key(_ target: CommandTarget, cwd: String?) -> String { target.key + "|" + (cwd ?? "") }

    /// The session and folder `status` answers for; nil while none has
    /// answered, so the panel can tell an answer for the old folder apart.
    var answeredKey: String? { status == nil ? nil : current?.key }

    func refresh(_ target: CommandTarget?, cwd: String?, revision: String? = nil) {
        guard let target else {
            current = nil
            self.revision = nil
            inFlightKey = nil
            lastProbe = nil
            if status != nil { status = nil }
            return
        }
        let key = Self.key(target, cwd: cwd)
        if key != current?.key {
            current = (target, key)
            self.revision = revision
            if status != nil { status = nil }
            probe(.newTarget)
        } else if revision != self.revision {
            self.revision = revision
            probe(.newRead)
        }
    }

    func appeared() { probe(.appeared) }

    private func probe(_ reason: GitProbeThrottle.Reason) {
        guard let current, inFlightKey != current.key else { return }
        let time = now()
        guard GitProbeThrottle.allows(reason, lastProbe: lastProbe, now: time) else { return }
        lastProbe = time
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
            let parsed = ContextGitProbe.parse(stdout)
            if status != parsed { status = parsed }
        case .failure:
            if status == nil { status = ContextGitProbe.parse("") }
        }
    }
}
