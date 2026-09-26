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
    private var settings: AppSettings = .empty
    private var inFlight: Set<String> = []
    private var generation = UUID()

    init(services: DevmachineServices = DevmachineServices()) {
        self.facade = ContextFacade(source: services.contextSource)
    }

    var isPolling: Bool { timer != nil }

    func start(_ target: CommandTarget, harnesses: Set<HarnessID> = [.claude], settings: AppSettings = .empty) {
        guard facade.supports(harnesses) else { stop(); return }
        if current == target, self.harnesses == harnesses, self.settings == settings, timer != nil { return }
        current = target
        self.harnesses = harnesses
        self.settings = settings
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
        let settings = self.settings
        let generation = self.generation
        Task.detached {
            let parsed = try? facade.context(for: target, harnesses: harnesses, settings: settings)
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

/// The context engine is the `devmachine-app` package's `context` entrypoint,
/// reached through the devmachine CLI (`DevmachineCLI.context`) rather than
/// run directly by the app.
enum LocalContext {
    /// A login shell's PATH is not inherited by an app started from Finder, and
    /// the script shells out to `git` and `gh`.
    static func environment(home: String = NSHomeDirectory()) -> [String: String] {
        ["PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
         "HOME": home]
    }
}
