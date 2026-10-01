import Foundation

/// What a CLI run left behind, kept whole: the result is read from stdout
/// and the person is shown stderr exactly as the CLI wrote it.
public struct CLIOutput: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// `devmachine --format json expose add|rm` (CLI 0.7.21 and newer).
public struct ExposeResult: Decodable, Equatable, Sendable {
    public enum Status: String, Decodable, Sendable {
        case published, pending, removed
    }

    public let host: String
    public let port: Int?
    public let workspace: String?
    public let applied: Bool
    public let status: Status
    public let note: String?
}

/// The card a publish or a removal shows while it runs and after: one line
/// per step, then the result.
public struct PublishProgress: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case publish
        case remove
    }

    public enum StepID: String, Equatable, Sendable {
        case config, dns, caddy
    }

    public enum StepState: Equatable, Sendable {
        case waiting, running, done, attention, failed, skipped
    }

    public struct Step: Equatable, Sendable, Identifiable {
        public let id: StepID
        public let title: String
        public let state: StepState
        public let detail: String?

        public init(_ id: StepID, _ title: String, _ state: StepState, detail: String? = nil) {
            self.id = id
            self.title = title
            self.state = state
            self.detail = detail
        }
    }

    public enum Outcome: Equatable, Sendable {
        case running
        case live(URL)
        case removed
        case saved(reason: String)
        case failed(details: String)
    }

    public let action: Action
    public let host: String
    public let steps: [Step]
    public let outcome: Outcome
    /// False only when the CLI stopped before it recorded anything, so
    /// nothing cached about the machine has to be read again.
    public let changedTheMachine: Bool

    public static let minimumVersion = "0.7.21"
    static let fallbackFailure = "Devmachine CLI failed."

    public var isFinished: Bool { outcome != .running }

    public func step(_ id: StepID) -> Step? { steps.first { $0.id == id } }

    public var headline: String {
        switch (outcome, action) {
        case (.running, .publish): return "Publishing \(host)…"
        case (.running, .remove): return "Removing \(host)…"
        case (.live(let url), _): return "Live: \(url.absoluteString)"
        case (.removed, _): return "Removed \(host)"
        case (.saved, .publish): return "Saved; will apply on next sync"
        case (.saved, .remove): return "Removed from the configuration; Caddy drops it on next sync"
        case (.failed, .publish): return "Couldn't publish \(host)"
        case (.failed, .remove): return "Couldn't remove \(host)"
        }
    }

    public var liveURL: URL? {
        if case .live(let url) = outcome { return url }
        return nil
    }

    public static func running(_ action: Action, host: String) -> PublishProgress {
        let steps: [Step]
        switch action {
        case .publish:
            steps = [Step(.dns, "DNS record", .running), Step(.caddy, "Caddy route", .waiting)]
        case .remove:
            steps = [Step(.config, "Configuration", .running), Step(.caddy, "Caddy route", .waiting)]
        }
        return PublishProgress(action: action, host: host, steps: steps, outcome: .running, changedTheMachine: false)
    }

    public static func couldNotStart(_ action: Action, host: String, message: String) -> PublishProgress {
        let skipped = running(action, host: host).steps.map { Step($0.id, $0.title, .skipped) }
        return PublishProgress(
            action: action, host: host, steps: skipped, outcome: .failed(details: message),
            changedTheMachine: false)
    }

    public static func finished(_ action: Action, host: String, output: CLIOutput) -> PublishProgress {
        let result = try? JSONDecoder().decode(ExposeResult.self, from: Data(output.stdout.utf8))
        let failure = output.exitCode == 0 ? nil : failureText(output)

        guard let result else {
            if let failure {
                return couldNotStart(action, host: host, message: failure)
            }
            return olderCLI(action, host: host, output: output)
        }

        let first = firstStep(action, output: output)
        let caddy: Step
        let outcome: Outcome
        if let failure {
            caddy = Step(.caddy, "Caddy refused the route", .failed, detail: result.note)
            outcome = .failed(details: failure)
        } else if result.applied {
            switch action {
            case .publish:
                caddy = Step(.caddy, "Caddy route applied", .done)
                outcome = .live(URL(string: "https://\(result.host)") ?? URL(string: "https://\(host)")!)
            case .remove:
                caddy = Step(.caddy, "Caddy dropped the route", .done)
                outcome = .removed
            }
        } else {
            let reason = result.note ?? "the machine has not applied it yet"
            caddy = Step(.caddy, "Caddy route pending", .attention, detail: reason)
            outcome = .saved(reason: reason)
        }
        return PublishProgress(
            action: action, host: host, steps: [first, caddy], outcome: outcome, changedTheMachine: true)
    }

    private static func firstStep(_ action: Action, output: CLIOutput) -> Step {
        switch action {
        case .remove:
            return Step(.config, "Configuration updated", .done)
        case .publish:
            if let record = manualRecord(in: output.stderr) {
                return Step(.dns, "Create the DNS record by hand", .attention, detail: record)
            }
            return Step(.dns, "DNS record set", .done)
        }
    }

    /// An installed provider writes the record without a word; with none,
    /// the CLI prints the record to create, one tab-separated line.
    private static func manualRecord(in stderr: String) -> String? {
        guard stderr.contains("Create this record by hand") else { return nil }
        let record = stderr.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.contains("\t") }
        return record.map { $0.split(separator: "\t").joined(separator: " ") }
    }

    private static func olderCLI(_ action: Action, host: String, output: CLIOutput) -> PublishProgress {
        let reason = "This devmachine CLI does not say whether Caddy applied it; "
            + "\(minimumVersion) or newer does. Run `devmachine expose list` to check."
        let steps = running(action, host: host).steps.map { step in
            step.id == .caddy
                ? Step(.caddy, "Caddy route not reported", .attention, detail: reason)
                : Step(step.id, step.id == .dns ? "DNS record set" : "Configuration updated", .done)
        }
        return PublishProgress(
            action: action, host: host, steps: steps, outcome: .saved(reason: reason), changedTheMachine: true)
    }

    private static func failureText(_ output: CLIOutput) -> String {
        let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        let stdout = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? fallbackFailure : stdout
    }
}
