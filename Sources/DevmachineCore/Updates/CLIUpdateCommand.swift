import Foundation

/// The `devmachine update` forms the app runs. None of them runs doctor or
/// sync, asks a question, or reaches a machine. From CLI 0.7.31 the CLI card
/// runs `--no-machines`: the CLI replaces itself first, then the new binary
/// pins the newest packages release and updates the skills on this Mac.
public enum CLIUpdateCommand: Equatable, Sendable {
    case cliOnly
    case noMachines
    case packagesOnly

    /// The first CLI release that knows `update --no-machines` and
    /// `packages outdated`.
    public static let noMachinesVersion = SemanticVersion(major: 0, minor: 7, patch: 31)

    public static func forCLI(installed: SemanticVersion) -> CLIUpdateCommand {
        installed >= noMachinesVersion ? .noMachines : .cliOnly
    }

    public var arguments: [String] {
        switch self {
        case .cliOnly: return CLISelfUpdate.arguments
        case .noMachines: return ["update", "--no-machines", "--format", "json"]
        case .packagesOnly: return ["update", "--no-machines", "--skip-cli", "--format", "json"]
        }
    }

    /// The JSON goes to stdout and the progress log to stderr.
    public var printsJSON: Bool { self != .cliOnly }

    private var flag: String { self == .cliOnly ? "--cli-only" : "--no-machines" }

    public func isUnknownFlag(_ lines: [String]) -> Bool {
        lines.contains { $0.contains("unknown flag: \(flag)") }
    }
}

/// What `update --no-machines --format json` printed. Each step is optional,
/// so a CLI that leaves one out still reads.
public struct CLIUpdateReport: Equatable, Sendable {
    public var cliFrom: String?
    public var cliTo: String?
    public var cliUpdated = false
    public var packagesFrom: String?
    public var packagesTo: String?
    public var packagesPinned = false
    public var skillsUpdated = false

    public init() {}

    public static func parse(_ stdout: Data) -> CLIUpdateReport? {
        guard let object = jsonObject(in: stdout),
              let wire = try? JSONDecoder().decode(Wire.self, from: object)
        else { return nil }
        var report = CLIUpdateReport()
        report.cliFrom = wire.cli?.from
        report.cliTo = wire.cli?.to
        report.cliUpdated = wire.cli?.updated ?? false
        report.packagesFrom = wire.packages?.from
        report.packagesTo = wire.packages?.to
        report.packagesPinned = wire.packages?.pinned ?? false
        report.skillsUpdated = wire.skills?.updated ?? false
        return report
    }

    /// "CLI updated to 0.8.0 · packages pinned v33 · skills updated". The CLI
    /// appears only when it changed: a skipped CLI is not news.
    public var summary: String {
        var parts: [String] = []
        if cliUpdated, let cliTo { parts.append("CLI updated to \(cliTo)") }
        return (parts + packagesAndSkills).joined(separator: " · ")
    }

    public var packagesAndSkills: [String] {
        var parts: [String] = []
        if packagesPinned, let packagesTo {
            parts.append("packages pinned \(packagesTo)")
        } else if let packagesTo {
            parts.append("packages already on \(packagesTo)")
        }
        parts.append(skillsUpdated ? "skills updated" : "skills already current")
        return parts
    }

    private static func jsonObject(in data: Data) -> Data? {
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return Data(text[start...end].utf8)
    }

    private struct Wire: Decodable {
        struct CLI: Decodable {
            var from: String?
            var to: String?
            var updated: Bool?
        }
        struct Packages: Decodable {
            var from: String?
            var to: String?
            var pinned: Bool?
        }
        struct Skills: Decodable {
            var updated: Bool?
        }
        var cli: CLI?
        var packages: Packages?
        var skills: Skills?
    }
}

/// `devmachine packages outdated --format json`. The CLI caches the newest
/// release for a day, so asking on every update check costs nothing.
public struct PackagesOutdated: Equatable, Sendable {
    public let pinned: String
    public let latest: String
    public let newer: Bool
    public let notesURL: URL?

    public init(pinned: String, latest: String, newer: Bool, notesURL: URL?) {
        self.pinned = pinned
        self.latest = latest
        self.newer = newer
        self.notesURL = notesURL
    }

    public static func parse(_ stdout: Data) throws -> PackagesOutdated {
        let wire = try JSONDecoder().decode(Wire.self, from: stdout)
        let notes = wire.notesURL.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        return PackagesOutdated(pinned: wire.pinned, latest: wire.latest, newer: wire.newer, notesURL: notes)
    }

    private struct Wire: Decodable {
        let pinned: String
        let latest: String
        let newer: Bool
        let notesURL: String?

        enum CodingKeys: String, CodingKey {
            case pinned, latest, newer
            case notesURL = "notes_url"
        }
    }
}

/// A packages release tag such as `v33`, compared by its numbers.
public struct PackagesVersion: Comparable, Hashable, Sendable {
    let parts: [Int]

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { piece -> Int? in
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(piece)
        }
        guard !pieces.isEmpty, numbers.count == pieces.count else { return nil }
        var trimmed = numbers
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        parts = trimmed
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        for (a, b) in zip(lhs.parts, rhs.parts) where a != b { return a < b }
        return lhs.parts.count < rhs.parts.count
    }
}

/// When the corner card offers a newer packages release. Later hides one
/// release and every older one; a running or finished update stays on
/// screen whatever Later said, the finished one until Close.
public enum PackagesUpdateToast {
    public enum Stage: Equatable, Sendable {
        case idle
        case running
        case done(closed: Bool)
        case failed
    }

    public static func isSupported(installed: SemanticVersion) -> Bool {
        installed >= CLIUpdateCommand.noMachinesVersion
    }

    public static func offered(_ outdated: PackagesOutdated?) -> PackagesOutdated? {
        guard let outdated, outdated.newer,
              !outdated.latest.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return outdated
    }

    public static func shows(stage: Stage, notice: PackagesOutdated?, laterVersion: String?) -> Bool {
        switch stage {
        case .running:
            return true
        case .done(let closed):
            return !closed
        case .idle, .failed:
            guard let notice else { return false }
            return !isPutOff(notice.latest, laterVersion: laterVersion)
        }
    }

    public static func isPutOff(_ latest: String, laterVersion: String?) -> Bool {
        guard let later = laterVersion, !later.isEmpty else { return false }
        guard let latestVersion = PackagesVersion(latest), let laterVersion = PackagesVersion(later) else {
            return latest == later
        }
        return latestVersion <= laterVersion
    }

    /// Whether an update already pinned `latest` or past it, so the card has
    /// nothing left to offer.
    public static func isCovered(latest: String, by report: CLIUpdateReport) -> Bool {
        guard let to = report.packagesTo else { return false }
        guard let pinned = PackagesVersion(to), let wanted = PackagesVersion(latest) else { return to == latest }
        return pinned >= wanted
    }
}
