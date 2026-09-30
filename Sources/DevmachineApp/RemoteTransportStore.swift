import Foundation
import DevmachineCore

/// Which transport each remote pane runs, and what the app learned about
/// each machine's mosh during this run.
@MainActor
final class RemoteTransportStore: ObservableObject {
    static let shared = RemoteTransportStore()

    struct Pane: Equatable {
        /// Nil while mosh-server is being started.
        var transport: RemoteTransport?
        var machine: String
        var reason: MoshFallbackReason?
        var detail: String
        var showsNotice: Bool

        var badgeHelp: String {
            switch transport {
            case .mosh?: return "Connected with mosh"
            case .ssh?: return reason.map { "ssh: " + $0.summary(machine: machine) } ?? "Connected with ssh"
            case nil: return "Connecting\u{2026}"
            }
        }

        var errorState: DMErrorState? {
            guard let reason else { return nil }
            return DMErrorState(
                systemImage: "antenna.radiowaves.left.and.right.slash",
                title: reason.notice(machine: machine),
                cause: reason.cause,
                details: detail)
        }
    }

    @Published private(set) var panes: [TerminalKind: Pane] = [:]
    private var memory = RemoteTransportMemory()
    let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func remembered(for machine: String) -> MoshFallbackReason? {
        memory.remembered(for: machine, now: now())
    }

    func connecting(_ kind: TerminalKind, machine: String) {
        panes[kind] = Pane(transport: nil, machine: machine, reason: nil, detail: "", showsNotice: false)
    }

    func usingMosh(_ kind: TerminalKind, machine: String) {
        panes[kind] = Pane(transport: .mosh, machine: machine, reason: nil, detail: "", showsNotice: false)
    }

    /// mosh heard back from the machine, so an old failure no longer holds.
    func moshConfirmed(machine: String) {
        memory.recordSuccess(for: machine)
    }

    /// `fresh` is an answer learned just now. One read back from memory is
    /// neither recorded again, which would push the re-probe back forever,
    /// nor announced on every pane of that machine.
    func usingSSH(
        _ kind: TerminalKind, machine: String, reason: MoshFallbackReason?, detail: String, fresh: Bool
    ) {
        if fresh, let reason { memory.record(reason, for: machine, at: now()) }
        panes[kind] = Pane(
            transport: .ssh, machine: machine, reason: reason, detail: detail,
            showsNotice: fresh && (reason?.showsNotice ?? false))
    }

    func dismissNotice(_ kind: TerminalKind) {
        panes[kind]?.showsNotice = false
    }

    /// "Try mosh again": the machine is asked afresh, not skipped for having
    /// failed before.
    func retry(_ kind: TerminalKind) {
        guard let pane = panes[kind] else { return }
        memory.forget(pane.machine)
        TerminalRegistry.shared.restart(kind)
    }

    func forget(_ kind: TerminalKind) {
        panes[kind] = nil
    }
}

/// Which machine hosts a workspace, from `devmachine workspaces list`, read
/// once per run. A failed read is not kept, so the next pane asks again.
final class MachineDirectory: @unchecked Sendable {
    static let shared = MachineDirectory()

    private let lock = NSLock()
    private var machines: [String: String]?

    func machine(forWorkspace workspace: String, load: () -> [String: String]?) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if machines == nil { machines = load() }
        return machines?[workspace]
    }
}
