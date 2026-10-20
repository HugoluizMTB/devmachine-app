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
        case keyNeedsPassword
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
        case .keyNeedsPassword: return "The key does not log in yet"
        case .loginRefused: return "The server refused the login"
        case .unreachable: return "The server could not be reached"
        }
    }

    public var whatToDo: String {
        switch cause {
        case .outdatedXcode:
            return "Update Xcode or its Command Line Tools in Software Update, then Retry."
        case .cliDownload:
            return "Check that this Mac is online and can reach mydevmachine.sh and github.com, then Retry."
        case .limaDownload:
            return "Check that this Mac is online and can reach github.com, then Retry."
        case .limaChecksum:
            return "The download did not match Lima's published checksum, so nothing was installed."
        case .limaMissing:
            return "Go Back and start again: the setup installs Lima first."
        case .hostKeyMismatch:
            return "Do not go on: the server answered with a different key than the one read before."
        case .keyNeedsPassword:
            return "Type the server's password once to put the key on it."
        case .loginRefused:
            return "Check the login, the key and the password, then Retry."
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
        if lowered.contains(MachineRetryField.keyNeedsPassword) { return .keyNeedsPassword }
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
                whatToDo: "Retry runs it again; the log shows why it stopped.",
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
        case .keyNeedsPassword:
            actions = [.editAnswers("Change answers")]
        case .loginRefused, .unreachable:
            actions = [.editAnswers("Check the answers"), .retry]
        }
        return SetupFailureHelp(title: advice.title, whatToDo: advice.whatToDo, actions: actions, cause: advice.cause)
    }

    /// What "Show details" holds: the exact command, then the last lines it printed.
    public static func details(for step: MachinePlanStep?, lines: [String], problem: String?) -> String {
        let tail = Array(lines.suffix(30))
        let command = step.map { "$ " + $0.displayLine }.flatMap { tail.contains($0) ? nil : [$0] } ?? []
        let body = tail.isEmpty ? [problem].compactMap { $0 } : tail
        return (command + body).joined(separator: "\n")
    }
}
