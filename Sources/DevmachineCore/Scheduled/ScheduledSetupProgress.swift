import Foundation

extension ScheduledRun {
    /// A task's newest run: the one `scheduled list` reported or one read
    /// with `scheduled runs`, whichever started later. Of two copies of one
    /// run, the one that ended wins: a run never goes back to running.
    public static func latest(listed: ScheduledRun?, read: [ScheduledRun]) -> ScheduledRun? {
        let newestRead = read.max { $0.startedAt < $1.startedAt }
        guard let listed else { return newestRead }
        guard let newestRead else { return listed }
        if newestRead.id == listed.id {
            return newestRead.status == .running ? listed : newestRead
        }
        return newestRead.startedAt > listed.startedAt ? newestRead : listed
    }
}

/// A workspace's first task, while `scheduled add --yes` sets the package
/// up: read from the lines the CLI prints on stderr as it goes. Only what
/// those lines prove moves it forward, so it never runs ahead of the CLI.
public struct ScheduledSetupProgress: Equatable, Sendable {
    public enum Phase: Int, Comparable, Sendable {
        case addingPackage, connecting, installing, creatingTask

        public static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Step: Equatable, Sendable {
        public enum State: Equatable, Sendable { case waiting, running, done }

        public let title: String
        public let state: State
        public let detail: String?
    }

    public let workspace: String
    public let machine: String
    public private(set) var phase: Phase = .addingPackage
    /// The Ansible task running now, without its role's name.
    public private(set) var current: String?
    /// The last few tasks that finished, oldest first.
    public private(set) var recent: [String] = []
    public private(set) var stepsStarted = 0

    public static let recentLimit = 3

    public init(workspace: String, machine: String) {
        self.workspace = workspace
        self.machine = machine
    }

    private static let taskHeader = try! NSRegularExpression(pattern: #"^(?:TASK|RUNNING HANDLER) \[(.+)\] \*+$"#)
    private static let colour = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*m")

    public mutating func read(_ raw: String) {
        let range = NSRange(raw.startIndex..., in: raw)
        let line = Self.colour.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if line.hasPrefix("PLAY RECAP") {
            advance(to: .creatingTask)
        } else if let name = Self.taskName(line) {
            guard phase <= .installing else { return }
            advance(to: .installing)
            if let current { recent = Array((recent + [current]).suffix(Self.recentLimit)) }
            current = name
            stepsStarted += 1
        } else if line.hasPrefix("PLAY [") {
            advance(to: .installing)
        } else if line.hasPrefix("added scheduled to ") || line.hasPrefix("scheduled is already on ") {
            advance(to: .connecting)
        }
    }

    private mutating func advance(to next: Phase) {
        if next > phase { phase = next }
    }

    private static func taskName(_ line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = taskHeader.firstMatch(in: line, range: range),
              let name = Range(match.range(at: 1), in: line)
        else { return nil }
        let full = String(line[name])
        guard let role = full.range(of: " : ") else { return full }
        return String(full[role.upperBound...])
    }

    public var steps: [Step] {
        func state(_ of: Phase) -> Step.State {
            of < phase ? .done : (of == phase ? .running : .waiting)
        }
        return [
            Step(title: "Add the scheduled package to \(workspace)", state: state(.addingPackage), detail: nil),
            Step(title: "Connect to \(machine)", state: state(.connecting), detail: nil),
            Step(title: "Install on \(machine)", state: state(.installing), detail: installDetail),
            Step(title: "Create the task", state: state(.creatingTask), detail: nil),
        ]
    }

    private var installDetail: String? {
        if phase > .installing {
            return stepsStarted == 0 ? nil : "\(stepsStarted) \(stepsStarted == 1 ? "step" : "steps") done"
        }
        guard phase == .installing, let current else { return nil }
        var lines = ["Step \(stepsStarted): \(current)"]
        if let last = recent.last { lines.append("Done: \(last)") }
        return lines.joined(separator: "\n")
    }
}
