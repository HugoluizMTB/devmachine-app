import Foundation
import Combine
import DevmachineCore

@MainActor
final class GitStore: ObservableObject {
    @Published var snapshot: GitSnapshot?
    @Published var errorText: String?
    @Published var isLoading = false

    private let host: HostRunner
    private var timer: Timer?
    private var current: CommandTarget?
    private var inFlight: String?

    init(host: HostRunner = HostRunner()) {
        self.host = host
    }

    func start(_ target: CommandTarget) {
        if current == target, timer != nil { return }
        current = target
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
        guard let target = current else { return }
        // Skip the tick while the read for this same target is still running;
        // a switch to another session still reads right away.
        let key = target.key
        guard inFlight != key else { return }
        inFlight = key
        // Loading is only the empty state: flipping it on every tick would
        // re-render the panel twice per poll for data that did not change.
        setLoading(snapshot == nil)
        let host = self.host
        Task.detached {
            let result = try? host.runCapturing(target, RemoteCommands.gitSnapshotBody)
            await MainActor.run {
                self.apply(result, target: target, key: key)
            }
        }
    }

    private func apply(
        _ result: (stdout: String, stderr: String, exitCode: Int32)?,
        target: CommandTarget,
        key: String
    ) {
        if inFlight == key { inFlight = nil }
        guard current == target else { return }
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
        guard let result else { return "Could not read the folder" }
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
