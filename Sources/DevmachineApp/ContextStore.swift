import Foundation
import Combine
import DevmachineCore

/// Where the panel's context read stands, so an empty panel can say whether
/// it is waiting, has nothing to show, or could not read.
enum ContextLoadStatus: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)

    static let unreadableAnswer = "The CLI answered in a format this app does not read."

    static func failure(_ error: Error) -> ContextLoadStatus {
        if error is DecodingError { return .failed(unreadableAnswer) }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(text.isEmpty ? "The context could not be read." : text)
    }
}

@MainActor
final class ContextStore: ObservableObject {
    @Published var state: ContextState? = nil
    @Published private(set) var status: ContextLoadStatus = .idle
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
        setStatus(.loading)
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
        setStatus(.idle)
    }

    /// An explicit read, from the panel's Retry button. With context already
    /// on screen the status stays as it is until the read answers, so the
    /// stale-data banner does not vanish and come back.
    func retry() {
        guard current != nil else { return }
        if state == nil {
            setStatus(.loading)
        }
        poll()
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
            let result = Result { try facade.context(for: target, harnesses: harnesses, settings: settings) }
            await MainActor.run {
                self.inFlight.remove(key)
                guard self.generation == generation else {
                    // A hidden panel can reopen while its old request finishes.
                    // Read again without publishing stale data or overlapping runs.
                    if self.current == target { self.poll() }
                    return
                }
                guard self.current == target else { return }
                self.publish(result)
            }
        }
    }

    /// A failed refresh keeps the last context on screen: it is still the
    /// best there is, and the panel says it is stale.
    private func publish(_ result: Result<ContextState?, Error>) {
        switch result {
        case .success(let parsed):
            // Assign only on a real change: the poll repeats every 5s and
            // a write to a @Published re-renders even for equal data.
            if state != parsed {
                state = parsed
            }
            setStatus(parsed == nil ? .empty : .loaded)
        case .failure(let error):
            setStatus(.failure(error))
        }
    }

    private func setStatus(_ new: ContextLoadStatus) {
        if status != new {
            status = new
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
