import Foundation
import Combine
import DevmachineCore

@MainActor
final class GitStore: ObservableObject {
    @Published var snapshot: GitSnapshot?
    @Published var errorText: String?
    @Published var isLoading = false

    private let remote: RemoteService
    private var timer: Timer?
    private var current: (alias: String, session: String)?
    private var inFlight: String?

    init(remote: RemoteService = RemoteService()) {
        self.remote = remote
    }

    func start(alias: String, session: String) {
        if let cur = current, cur.alias == alias, cur.session == session, timer != nil {
            return
        }
        current = (alias, session)
        clear()
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        current = nil
        inFlight = nil
        clear()
    }

    func refresh() {
        guard let (alias, session) = current else { return }
        // Skip the tick while the ssh for this same session is still running;
        // a switch to another session still reads right away.
        let key = "\(alias)/\(session)"
        guard inFlight != key else { return }
        inFlight = key
        // Loading is only the empty state: flipping it on every tick would
        // re-render the panel twice per poll for data that did not change.
        setLoading(snapshot == nil)
        let remote = self.remote
        let command = RemoteCommands.gitSnapshot(session: session)
        Task.detached {
            let result = try? remote.runCapturing(alias: alias, args: [command])
            await MainActor.run {
                self.apply(result, alias: alias, session: session, key: key)
            }
        }
    }

    private func apply(
        _ result: (stdout: String, stderr: String, exitCode: Int32)?,
        alias: String,
        session: String,
        key: String
    ) {
        if inFlight == key { inFlight = nil }
        guard let cur = current, cur.alias == alias, cur.session == session else { return }
        setLoading(false)
        let parsed = result.flatMap { GitSnapshotParser.parse($0.stdout) }
        if snapshot != parsed {
            snapshot = parsed
        }
        let failure = parsed == nil ? Self.failure(result) : nil
        if errorText != failure {
            errorText = failure
        }
    }

    // No snapshot and no message means "not a git repository", which the view words itself.
    private static func failure(_ result: (stdout: String, stderr: String, exitCode: Int32)?) -> String? {
        guard let result else { return "Could not reach the host" }
        let line = result.stderr
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line, !line.localizedCaseInsensitiveContains("not a git repository") else { return nil }
        return line
    }

    private func setLoading(_ value: Bool) {
        if isLoading != value {
            isLoading = value
        }
    }

    private func clear() {
        if snapshot != nil { snapshot = nil }
        if errorText != nil { errorText = nil }
    }
}
