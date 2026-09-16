import Foundation
import Combine
import DevmachineCore

/// Where the context engine runs. A remote session is read over ssh on the
/// host that owns it; a local one runs the same script on this Mac.
enum ContextTarget: Equatable {
    case remote(alias: String, session: String)
    case local(path: String)

    var key: String {
        switch self {
        case let .remote(alias, session): return "\(alias)/\(session)"
        case let .local(path): return "local:\(path)"
        }
    }
}

@MainActor
final class ContextStore: ObservableObject {
    @Published var state: ContextState? = nil
    private let remote: RemoteService
    private let local: CommandRunner
    private var timer: Timer?
    private var current: ContextTarget?
    private var inFlight: String?

    init(remote: RemoteService = RemoteService(), local: CommandRunner = ProcessRunner()) {
        self.remote = remote
        self.local = local
    }

    var isPolling: Bool { timer != nil }

    func start(_ target: ContextTarget) {
        if current == target, timer != nil { return }
        current = target
        clearState()
        poll()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        current = nil
        inFlight = nil
        clearState()
    }

    func poll() {
        guard let target = current else { return }
        // Skip the tick while the run for this same target is still going; a
        // switch to another session still polls right away.
        let key = target.key
        guard inFlight != key else { return }
        inFlight = key
        let remote = self.remote
        let local = self.local
        Task.detached {
            let out: String?
            switch target {
            case let .remote(alias, session):
                out = try? remote.run(
                    alias: alias, args: ["devmachine-infer", "--session", session])
            case let .local(path):
                out = try? local.run(
                    executable: LocalContext.scriptPath,
                    args: LocalContext.arguments(path: path),
                    environment: LocalContext.environment())
            }
            let parsed: ContextState? = out
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONDecoder().decode(ContextState.self, from: $0) }
            await MainActor.run {
                if self.inFlight == key { self.inFlight = nil }
                guard self.current == target else { return }
                // Assign only on a real change: the poll repeats every 5s and
                // a write to a @Published re-renders even for equal data.
                if self.state != parsed {
                    self.state = parsed
                }
            }
        }
    }

    private func clearState() {
        if state != nil {
            state = nil
        }
    }
}

/// The context engine as it runs on this Mac. Installed by the operator repo
/// (`ansible/mac.yml --tags mac_infer`), the same script the hosts run.
enum LocalContext {
    static var scriptPath: String {
        NSHomeDirectory() + "/.local/bin/devmachine-infer"
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: scriptPath)
    }

    /// No session name: `zmx` is not `tmux`, so the folder is passed straight in.
    static func arguments(path: String) -> [String] {
        ["--project", (path as NSString).expandingTildeInPath]
    }

    /// A login shell's PATH is not inherited by an app started from Finder, and
    /// the script shells out to `git` and `gh`.
    static func environment(home: String = NSHomeDirectory()) -> [String: String] {
        ["PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
         "HOME": home]
    }
}
