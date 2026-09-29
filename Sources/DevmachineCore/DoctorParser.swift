import Foundation

/// One `devmachine doctor` check's result.
public enum DoctorStatus: String, Codable, Equatable, Sendable {
    case pass, warn, fail, skip
}

/// One row `devmachine doctor` reports: a check name, its status, and a
/// detail string that, on `fail`, is usually the fix command to run.
public struct DoctorCheck: Equatable, Sendable, Identifiable {
    public let name: String
    public let status: DoctorStatus
    public let detail: String

    public var id: String { name }

    public init(name: String, status: DoctorStatus, detail: String) {
        self.name = name
        self.status = status
        self.detail = detail
    }
}

extension DoctorCheck: Decodable {
    enum CodingKeys: String, CodingKey { case name, status, detail }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let rawStatus = try container.decode(String.self, forKey: .status)
        // An unrecognized status is a CLI the app has not caught up with yet;
        // reporting it as a failure is the safe read, never a silent pass.
        status = DoctorStatus(rawValue: rawStatus) ?? .fail
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
    }
}

/// `devmachine doctor --format json`'s whole answer: every check it ran, and
/// whether the machine is healthy overall.
public struct DoctorReport: Decodable, Equatable, Sendable {
    public let checks: [DoctorCheck]
    public let ok: Bool

    public init(checks: [DoctorCheck], ok: Bool) {
        self.checks = checks
        self.ok = ok
    }
}

/// Turns `devmachine doctor`'s output into a `DoctorReport`, JSON first and a
/// defensive read of its plain-text table as a fallback for a CLI run
/// without `--format json`.
public enum DoctorParser {
    public static func parse(_ output: String) -> DoctorReport? {
        if let data = output.data(using: .utf8),
           let report = try? JSONDecoder().decode(DoctorReport.self, from: data) {
            return report
        }
        let checks = parseTable(output)
        guard !checks.isEmpty else { return nil }
        return DoctorReport(checks: checks, ok: checks.allSatisfy { $0.status != .fail })
    }

    /// Reads `cmd.Printf("%-4s  %-*s  %s\n", status, name, detail)`: a status
    /// word (always 4 letters), then the name and detail, each field
    /// separated by two or more spaces.
    static func parseTable(_ output: String) -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let fields = line
                .components(separatedBy: "  ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard fields.count >= 2, let status = DoctorStatus(rawValue: fields[0]) else { continue }
            let detail = fields.count > 2 ? fields[2...].joined(separator: "  ") : ""
            checks.append(DoctorCheck(name: fields[1], status: status, detail: detail))
        }
        return checks
    }
}
