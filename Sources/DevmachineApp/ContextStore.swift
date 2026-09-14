import Foundation
import Combine
import DevmachineCore

@MainActor
final class ContextStore: ObservableObject {
    @Published var state: ContextState? = nil
    private let remote: RemoteService
    private var timer: Timer?
    private var current: (alias: String, session: String)?
    private var inFlight: String?

    init(remote: RemoteService = RemoteService()) {
        self.remote = remote
    }

    var isPolling: Bool { timer != nil }

    func start(alias: String, session: String) {
        if let cur = current, cur.alias == alias, cur.session == session, timer != nil {
            return
        }
        current = (alias, session)
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
        guard let (alias, session) = current else { return }
        // Skip the tick while the ssh for this same session is still running;
        // a switch to another session still polls right away.
        let key = "\(alias)/\(session)"
        guard inFlight != key else { return }
        inFlight = key
        let remote = self.remote
        Task.detached {
            let out = try? remote.run(alias: alias, args: ["devmachine-infer", "--session", session])
            let parsed: ContextState? = out
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONDecoder().decode(ContextState.self, from: $0) }
            await MainActor.run {
                if self.inFlight == key { self.inFlight = nil }
                guard let cur = self.current, cur.alias == alias, cur.session == session else { return }
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
