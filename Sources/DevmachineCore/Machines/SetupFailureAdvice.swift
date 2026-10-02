import Foundation

/// What a failed setup step's log means, in plain words, and what to do.
/// Only causes the log names for sure are recognised; anything else gets
/// no advice and the log speaks for itself. The last line that names a
/// cause wins: an earlier one was often retried past.
public struct SetupFailureAdvice: Equatable, Sendable {
    public enum Cause: String, CaseIterable, Sendable {
        case outdatedXcode
        case cliDownload
        case limaDownload
        case limaChecksum
        case limaMissing
        case hostKeyMismatch
        case loginRefused
        case unreachable
    }

    public let cause: Cause

    public init(cause: Cause) {
        self.cause = cause
    }

    public var title: String {
        switch cause {
        case .outdatedXcode: return "Xcode is too old for Homebrew"
        case .cliDownload: return "The devmachine CLI could not be downloaded"
        case .limaDownload: return "Lima could not be downloaded"
        case .limaChecksum: return "Lima's download did not check out"
        case .limaMissing: return "Lima is not installed"
        case .hostKeyMismatch: return "The server's key is not the one you confirmed"
        case .loginRefused: return "The server refused the login"
        case .unreachable: return "The server could not be reached"
        }
    }

    public var whatToDo: String {
        switch cause {
        case .outdatedXcode:
            return "Homebrew refuses to work while Xcode or its Command Line Tools are behind. Update them in "
                + "System Settings → General → Software Update, then Retry. The devmachine CLI itself installs "
                + "without Homebrew, so only a step that uses Homebrew needs this."
        case .cliDownload:
            return "Check that this Mac is online and can reach mydevmachine.sh and github.com, then Retry. "
                + "Nothing was installed."
        case .limaDownload:
            return "Check that this Mac is online and can reach github.com, then Retry. Nothing was installed."
        case .limaChecksum:
            return "The file from GitHub does not match Lima's published checksum, so it was not installed. "
                + "Retry downloads it again; if it keeps failing, something between this Mac and GitHub changes it."
        case .limaMissing:
            return "The machine on this Mac needs Lima. Go Back and start again: the setup installs it first."
        case .hostKeyMismatch:
            return "The server answered with a different key than the one you checked in your provider's console. "
                + "Go Back, read the key again and compare it with the console. Do not go on if they differ."
        case .loginRefused:
            return "The key or the password was not accepted. Go Back and check the login, the key and the "
                + "password your provider gave you, then Retry."
        case .unreachable:
            return "Check the address and the SSH port, and that the server is running, then Retry."
        }
    }

    public static func advice(for step: MachinePlanStep.Kind, lines: [String]) -> SetupFailureAdvice? {
        for line in lines.reversed() {
            if let cause = cause(of: line, step: step) { return SetupFailureAdvice(cause: cause) }
        }
        return nil
    }

    private static func cause(of line: String, step: MachinePlanStep.Kind) -> Cause? {
        let lowered = line.lowercased()
        func mentions(_ needles: [String]) -> Bool { needles.contains { lowered.contains($0) } }
        if mentions(["xcode", "command line tools"]), mentions(["outdated", "too old", "update to"]) {
            return .outdatedXcode
        }
        if step == .installCLI {
            if mentions(["could not resolve", "failed to connect", "timed out", "offline", "curl: ("]) {
                return .cliDownload
            }
            return nil
        }
        if step == .installLima {
            if mentions(["checksum", "sha256sums"]) { return .limaChecksum }
            if mentions(["offline", "could not connect", "network", "timed out", "answered", "could not be found",
                         "did not say which lima release"]) {
                return .limaDownload
            }
            return nil
        }
        if lowered.contains("limactl"), mentions(["not found", "install lima"]) { return .limaMissing }
        if mentions(["remote host identification has changed", "host key verification failed"])
            || (mentions(["fingerprint", "host key"]) && mentions(["does not match", "mismatch", "changed"])) {
            return .hostKeyMismatch
        }
        if FailureCause.isSSHLoginRefused(line) { return .loginRefused }
        if mentions(["connection refused", "no route to host", "could not resolve", "operation timed out",
                     "connection timed out", "network is unreachable", "host is down"]) {
            return .unreachable
        }
        return nil
    }
}

/// What a failure panel shows: a cause recognised from the log with its
/// own steps, or generic next steps that still say what the step was doing
/// and the exact command. Every failure gets one.
public struct SetupFailureHelp: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case retry
        /// Back to the answers, to change one.
        case editAnswers(String)
        case open(String, URL)
    }

    public static let softwareUpdate = URL(string: "x-apple.systempreferences:com.apple.preferences.softwareupdate")!
    public static let xcodeDownloads = URL(string: "https://developer.apple.com/xcode/")!

    public let title: String
    public let whatToDo: String
    public let actions: [Action]
    public let cause: SetupFailureAdvice.Cause?

    public static func help(for step: MachinePlanStep, lines: [String]) -> SetupFailureHelp {
        guard let advice = SetupFailureAdvice.advice(for: step.kind, lines: lines) else {
            return SetupFailureHelp(
                title: "\(step.title) did not finish",
                whatToDo: "This step ran: \(step.displayLine)\nThe last lines of the log below say why it stopped. "
                    + "Retry runs it again, and only it: the steps already done are skipped. If your answers "
                    + "were wrong, change them and run again. If it keeps failing, copy the log or report a bug.",
                actions: [.retry, .editAnswers("Change answers")], cause: nil)
        }
        let actions: [Action]
        switch advice.cause {
        case .outdatedXcode:
            actions = [.open("Open Software Update", softwareUpdate), .open("Xcode downloads", xcodeDownloads), .retry]
        case .cliDownload, .limaDownload, .limaChecksum:
            actions = [.retry]
        case .limaMissing:
            actions = [.editAnswers("Back")]
        case .hostKeyMismatch:
            actions = [.editAnswers("Read the key again")]
        case .loginRefused, .unreachable:
            actions = [.editAnswers("Check the answers"), .retry]
        }
        return SetupFailureHelp(title: advice.title, whatToDo: advice.whatToDo, actions: actions, cause: advice.cause)
    }
}
