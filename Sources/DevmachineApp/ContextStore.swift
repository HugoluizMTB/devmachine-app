import Foundation
import Combine
import DevmachineCore

@MainActor
final class ContextStore: ObservableObject {
    @Published var state: ContextState? = nil
    private let facade: ContextFacade
    private var timer: Timer?
    private var current: CommandTarget?
    private var harnesses: Set<HarnessID> = []
    private var inFlight: Set<String> = []
    private var generation = UUID()

    init(services: DevmachineServices = DevmachineServices()) {
        self.facade = ContextFacade(source: services.contextSource)
    }

    var isPolling: Bool { timer != nil }

    func start(_ target: CommandTarget, harnesses: Set<HarnessID> = [.claude]) {
        guard facade.supports(harnesses) else { stop(); return }
        if current == target, self.harnesses == harnesses, timer != nil { return }
        current = target
        self.harnesses = harnesses
        generation = UUID()
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
        generation = UUID()
        clearState()
    }

    func poll() {
        guard let target = current else { return }
        // Skip the tick while the run for this same target is still going; a
        // switch to another session still polls right away.
        let key = target.key
        guard inFlight.insert(key).inserted else { return }
        let facade = self.facade
        let harnesses = self.harnesses
        let generation = self.generation
        Task.detached {
            let parsed = try? facade.context(for: target, harnesses: harnesses)
            await MainActor.run {
                self.inFlight.remove(key)
                guard self.generation == generation else {
                    // A hidden panel can reopen while its old request finishes.
                    // Read again without publishing stale data or overlapping runs.
                    if self.current == target { self.poll() }
                    return
                }
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
    /// One engine, two sides: the host already has `devmachine-infer` on its
    /// PATH, and here it is the script this Mac installed.
    static func command(for target: CommandTarget) -> String {
        switch target {
        case let .remote(_, session):
            return "devmachine-infer --session \(RemoteCommands.shellSingleQuoted(session))"
        case let .local(_, path):
            return RemoteCommands.shellSingleQuoted(scriptPath)
                + " --project "
                + RemoteCommands.shellSingleQuoted((path as NSString).expandingTildeInPath)
        }
    }

    static var scriptPath: String {
        NSHomeDirectory() + "/.local/bin/devmachine-infer"
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: scriptPath)
    }

    /// A login shell's PATH is not inherited by an app started from Finder, and
    /// the script shells out to `git` and `gh`.
    static func environment(home: String = NSHomeDirectory()) -> [String: String] {
        ["PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
         "HOME": home]
    }
}
