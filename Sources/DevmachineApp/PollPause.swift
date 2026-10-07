import Foundation

/// One workspace held back from every automatic login after ssh failed for
/// it. A refused login pauses that workspace alone: fail2ban counts failed
/// logins per machine and source IP, so asking again soon is what bans this
/// Mac, while another account's working login adds nothing. A second
/// workspace refused on the same machine inside the first one's pause pauses
/// the whole machine, so a locked agent costs at most two refused logins per
/// machine per pause. An unreachable machine pauses its own workspaces, since
/// none of them can answer.
struct PollPause: Equatable {
    enum Reason: Equatable {
        case loginRefused
        case unreachable
        case machineLoginsRefused

        /// Paused for the whole machine, so the sidebar shows one card for it.
        var coversMachine: Bool { self != .loginRefused }
    }

    /// A locked agent after waking refuses every login until someone unlocks
    /// it, and each refusal counts toward a ban: 5 minutes keeps a sweep from
    /// stacking them. A host that does not answer costs nothing to ask, so it
    /// is asked again sooner.
    static let loginRefusedSeconds: TimeInterval = 300
    static let unreachableSeconds: TimeInterval = 60

    let reason: Reason
    let machine: String?
    let until: Date

    init(reason: Reason, machine: String?, until: Date) {
        self.reason = reason
        self.machine = machine
        self.until = until
    }

    init(_ reason: Reason, machine: String?, from now: Date) {
        let seconds = reason == .unreachable ? Self.unreachableSeconds : Self.loginRefusedSeconds
        self.init(reason: reason, machine: machine, until: now.addingTimeInterval(seconds))
    }

    func notice(workspace: String) -> String {
        switch reason {
        case .loginRefused:
            let target = machine ?? "its machine"
            return "Login refused for \(workspace). Paused checking it for 5 min "
                + "so \(target) doesn't block this Mac's IP."
        case .machineLoginsRefused:
            let target = machine ?? workspace
            return "Logins to several workspaces on \(target) were refused. Paused checking \(target) "
                + "for 5 min so it doesn't block this Mac's IP."
        case .unreachable:
            if let machine { return "Couldn't reach \(machine). Paused checking its workspaces for 1 min." }
            return "Couldn't reach \(workspace). Paused checking it for 1 min."
        }
    }
}
