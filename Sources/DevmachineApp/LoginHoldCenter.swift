import Combine
import DevmachineCore
import Foundation

/// The app's one record of machines that refused this Mac's login. Every
/// automatic call that logs into a machine (sessions, stats, doctor, the
/// Context, Files and Git tabs, widgets) asks it first, and each failure
/// is reported back: fail2ban counts every refused login toward a ban of
/// this Mac's IP, whichever part of the app made it.
@MainActor
final class LoginHoldCenter: ObservableObject {
    /// Under XCTest each store gets its own center unless a test hands one
    /// in, so a refusal in one test never holds a machine in another.
    static let shared = LoginHoldCenter()

    static func live() -> LoginHoldCenter {
        NSClassFromString("XCTestCase") == nil ? shared : LoginHoldCenter()
    }

    @Published private(set) var holds = LoginHolds()

    /// Makes Retry's one attempt for a machine. Nil, or one that finds
    /// nothing to try with, leaves the hold as it was.
    var attempt: (@MainActor (String) -> Bool)?

    var machineForWorkspace: @MainActor (String) -> String? = {
        MachineReadinessStore.shared.machine(forWorkspace: $0)
    }

    private var configurationWatch: AnyCancellable?

    func isHeld(machine: String) -> Bool { holds.isHeld(machine) }

    func hold(for machine: String) -> LoginHolds.Hold? { holds.hold(for: machine) }

    func machine(for target: WidgetTarget) -> String? {
        switch target {
        case .local: return nil
        case let .machine(name): return name
        case let .workspace(name): return machineForWorkspace(name)
        }
    }

    func isHeld(target: WidgetTarget) -> Bool {
        machine(for: target).map(isHeld(machine:)) ?? false
    }

    func record(message: String, machine: String) {
        record(LoginFailure(message: message), detail: message, machine: machine)
    }

    func record(_ failure: LoginFailure?, detail: String, machine: String) {
        var next = holds
        next.record(failure, detail: detail, machine: machine)
        if next != holds { holds = next }
    }

    func recordSuccess(machine: String) {
        var next = holds
        next.recordSuccess(machine: machine)
        if next != holds { holds = next }
    }

    /// The Retry button: one attempt, whose answer ends or renews the hold.
    func retry(machine: String) {
        guard holds.beginRetry(machine) else { return }
        if attempt?(machine) != true { holds.endRetry(machine) }
    }

    /// Told which machines a configuration change released, once the
    /// holds no longer name them.
    var onReleased: (@MainActor (Set<String>) -> Void)?

    func configurationRead(_ entries: [String: String]) {
        var next = holds
        let released = next.configurationRead(entries)
        if next != holds { holds = next }
        if !released.isEmpty { onReleased?(released) }
    }

    /// Follows each machine's login entry as the readiness check reads the
    /// CLI's configuration.
    func follow<Entries: Publisher>(_ entries: Entries) where Entries.Output == [String: String]?, Entries.Failure == Never {
        configurationWatch = entries.compactMap { $0 }.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] next in
            MainActor.assumeIsolated { self?.configurationRead(next) }
        }
    }
}
