import Foundation

/// What the error card in a conversation says and offers, per error kind.
public struct ChatFailurePresentation: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case logIn
        case chooseAnotherWorkspace
        case openPackages
        case openMachines
        case updateCLI
        case tryAgain
    }

    public enum Tone: Equatable, Sendable {
        case warning
        case error
    }

    public let title: String
    public let body: String
    public let actions: [Action]
    public let tone: Tone
    public let symbol: String

    public init(failure: ChatFailure, harness: HarnessID, place: ChatPlace) {
        let name = ChatHarness.title(harness)
        let command = harness.rawValue
        let whereName = place.workspaceName ?? "This Mac"
        let onWhere = place.workspaceName.map { "on \($0)" } ?? "on this Mac"
        let remote = place.workspaceName != nil
        switch failure.kind {
        case .harnessLoggedOut:
            title = "\(name) is not logged in \(onWhere)"
            body = "The \(command) CLI \(onWhere) has no login, so it cannot answer. Log in once "
                + (remote ? "on that workspace" : "on this Mac")
                + " and this chat sends your message again. Or ask from another workspace where \(name) is logged in."
            actions = [.logIn, .chooseAnotherWorkspace]
            tone = .warning
            symbol = "person.crop.circle.badge.exclamationmark"
        case .harnessMissing:
            title = "\(name) is not installed \(onWhere)"
            let package = ChatHarness.package(harness).map { "the \($0) package" } ?? "its package"
            body = "The \(command) command was not found \(onWhere). "
                + (remote
                    ? "Add \(package) to \(whereName) and sync it, then try again."
                    : "Install the \(command) CLI on this Mac, then try again.")
                + " Or ask from another workspace."
            actions = (remote ? [.openPackages] : []) + [.chooseAnotherWorkspace, .tryAgain]
            tone = .warning
            symbol = "shippingbox"
        case .unreachable:
            title = "\(whereName) cannot be reached"
            body = "The machine did not answer. Check that it is on and on the network, then try again."
            actions = [.tryAgain, .chooseAnotherWorkspace]
            tone = .error
            symbol = "wifi.exclamationmark"
        case .loginRefused:
            title = "\(whereName) refused the login"
            body = "The machine answered but did not accept the ssh key. Check the ssh agent in Settings, "
                + "then try again."
            actions = [.tryAgain, .chooseAnotherWorkspace]
            tone = .error
            symbol = "key.slash"
        case .hostKeyRejected:
            title = "\(whereName)'s host key changed"
            body = "The machine answered with a host key this Mac does not trust. Check it in Settings → Machines "
                + "before you try again."
            actions = [.openMachines, .chooseAnotherWorkspace]
            tone = .error
            symbol = "lock.trianglebadge.exclamationmark"
        case .needsNewerCLI:
            title = "Chats need a newer devmachine CLI"
            body = "The installed CLI has no chat command yet. Update it, then try again."
            actions = [.updateCLI, .tryAgain]
            tone = .warning
            symbol = "arrow.down.circle"
        case .refused:
            title = "The chat could not start"
            body = Self.firstLine(failure.message)
            actions = [.chooseAnotherWorkspace, .tryAgain]
            tone = .error
            symbol = "exclamationmark.triangle"
        case .sessionNotFound:
            title = "The session is gone"
            body = "Ask could not find this session \(onWhere). It may have ended."
            actions = [.tryAgain]
            tone = .warning
            symbol = "questionmark.circle"
        case .transcriptNotFound:
            title = "No transcript for this session yet"
            body = "\(name) has not written anything to read for this session. Try again once it has answered."
            actions = [.tryAgain]
            tone = .warning
            symbol = "doc.text.magnifyingglass"
        case .harnessUnsupported:
            title = "Ask is not available for this session"
            body = "Ask works with Claude and Codex sessions."
            actions = []
            tone = .warning
            symbol = "questionmark.circle"
        case let .other(kind) where kind == "cli-not-found":
            title = "The devmachine CLI was not found"
            body = "Install the devmachine CLI, then try again."
            actions = [.tryAgain]
            tone = .error
            symbol = "exclamationmark.triangle"
        case .harnessFailed, .other, .cancelled:
            title = "\(name) could not answer"
            body = "It stopped with an error. The details show what it said."
            actions = [.tryAgain, .chooseAnotherWorkspace]
            tone = .error
            symbol = "exclamationmark.triangle"
        }
    }

    static func firstLine(_ message: String) -> String {
        var line = message.split(separator: "\n").first.map(String.init) ?? message
        if line.lowercased().hasPrefix("error:") { line = String(line.dropFirst(6)) }
        line = line.trimmingCharacters(in: .whitespaces)
        return line.prefix(1).uppercased() + line.dropFirst()
    }
}
