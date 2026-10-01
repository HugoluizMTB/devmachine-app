import Foundation
import DevmachineCore

/// Why a workspace's sessions could not be listed, said plainly with what
/// fixes it, in place of a list that would otherwise just be empty.
enum SessionProblem: Equatable {
    case aliasMissing(alias: String)
    case tmuxMissing(detail: String)
    case loginRefused(detail: String)
    case unreachable(detail: String)
    case failed(detail: String)

    init(_ error: Error) {
        if let list = error as? SessionListError {
            switch list.problem {
            case let .aliasMissing(alias): self = .aliasMissing(alias: alias)
            case .tmuxMissing: self = .tmuxMissing(detail: list.stderr)
            }
            return
        }
        if let store = error as? SessionStoreError {
            switch store.failure {
            case .authDenied: self = .loginRefused(detail: store.stderr)
            case .unreachable: self = .unreachable(detail: store.stderr)
            }
            return
        }
        self = .failed(detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    /// The command that fixes it, when there is one to run on this Mac.
    static let writeAliasesCommand = "devmachine aliases --write"

    func presentation(workspace: String) -> SessionProblemPresentation {
        switch self {
        case let .aliasMissing(alias):
            return SessionProblemPresentation(
                title: "\(workspace) has no SSH alias yet",
                cause: "ssh found no Host entry named \(alias). The CLI writes one for each workspace "
                    + "into your SSH configuration once you let it.",
                commands: [Self.writeAliasesCommand],
                details: "ssh: Could not resolve hostname \(alias)")
        case let .tmuxMissing(detail):
            return SessionProblemPresentation(
                title: "tmux isn't installed for \(workspace)",
                cause: "The login worked, but the shell has no tmux, which sessions run in. "
                    + "Install it on the machine, then try again.",
                commands: [],
                details: detail.isEmpty ? "tmux: command not found (exit 127)" : detail)
        case let .loginRefused(detail):
            return SessionProblemPresentation(
                title: "Couldn't list \(workspace)'s sessions",
                cause: FailureCause.permissionDenied.summary + " Unlock your SSH agent, then try again.",
                commands: [], details: detail)
        case let .unreachable(detail):
            return SessionProblemPresentation(
                title: "Couldn't list \(workspace)'s sessions",
                cause: FailureCause(message: detail)?.summary ?? FailureCause.unreachable.summary,
                commands: [], details: detail)
        case let .failed(detail):
            return SessionProblemPresentation(
                title: "Couldn't list \(workspace)'s sessions",
                cause: FailureCause(message: detail)?.summary,
                commands: [], details: detail)
        }
    }
}

struct SessionProblemPresentation: Equatable {
    let title: String
    let cause: String?
    let commands: [String]
    let details: String
}
