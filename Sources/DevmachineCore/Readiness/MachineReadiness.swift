import Foundation

/// Whether a machine has what the app runs on it: the `devmachine-app`
/// package, asked for in the configuration and applied by a sync.
public enum MachineReadiness: Equatable, Sendable {
    case ready
    /// The configuration does not ask for the package on this machine.
    case notDeclared
    /// The configuration asks for it, but no sync has applied it yet.
    case notApplied
    /// It is there, from a release older than this app needs.
    case outdated(detail: String)
    /// Could not tell (no CLI, offline, a read failed). The app fails open:
    /// a flaky read must not put a "not ready" card on a working machine.
    case unknown

    public var needsPrepare: Bool {
        self == .notDeclared || self == .notApplied
    }

    public var needsAttention: Bool {
        switch self {
        case .notDeclared, .notApplied, .outdated: return true
        case .ready, .unknown: return false
        }
    }
}

/// What a call into the package said about the machine, from the CLI's own
/// error text.
public enum PackageCallFailure: Equatable, Sendable {
    case notInstalled
    case outdated(detail: String)

    /// Matches the CLI's wording (`internal/dns/open.go`, `external.go`):
    /// "devmachine-app is not installed on main. Add it with …" and
    /// "devmachine-app does not accept "stats". It accepts context". A lock
    /// that names the package while the machine lacks its files fails in the
    /// machine's shell, on the entrypoint's path.
    public static func classify(_ detail: String, package: String = MachinePrepare.package) -> PackageCallFailure? {
        if detail.contains("\(package) does not accept") {
            return .outdated(detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if detail.contains("\(package) is not installed on") {
            return .notInstalled
        }
        let entrypoint = "/\(package)/bin/\(package)"
        if detail.contains(entrypoint),
           detail.contains("No such file or directory") || detail.contains("not found") {
            return .notInstalled
        }
        return nil
    }

    /// The machine the CLI named in "… is not installed on <machine>", when
    /// it named one.
    public static func machine(in detail: String, package: String = MachinePrepare.package) -> String? {
        let marker = "\(package) is not installed on "
        guard let range = detail.range(of: marker) else { return nil }
        let rest = detail[range.upperBound...]
        let name = rest.prefix { !$0.isWhitespace && $0 != "." && $0 != "," }
        return name.isEmpty ? nil : String(name)
    }
}

public enum ReadinessCheck {
    /// `declared` comes from `packages list`, `applied` from the lock, and
    /// `observed` from the last call into the package that failed. A nil
    /// input is one the app could not read.
    public static func evaluate(declared: Bool?, applied: Bool?, observed: PackageCallFailure?) -> MachineReadiness {
        switch observed {
        case let .outdated(detail):
            return .outdated(detail: detail)
        case .notInstalled:
            return declared == false ? .notDeclared : .notApplied
        case nil:
            break
        }
        guard let declared else { return .unknown }
        guard declared else { return .notDeclared }
        return applied == false ? .notApplied : .ready
    }
}

/// The two commands that make a machine ready, run in the background with
/// their log shown. `--tags` applies only this package: a plain sync would
/// also apply whatever else is waiting in the configuration, which is not
/// what a button called Prepare should do.
public enum MachinePrepare {
    public static let package = "devmachine-app"

    /// The first CLI whose `sync --tags` records in the lock only the
    /// packages it applied.
    public static let minimumCLIVersion = SemanticVersion(major: 0, minor: 7, patch: 24)

    public static func canPrepareInApp(cliVersion: SemanticVersion?) -> Bool {
        guard let cliVersion else { return false }
        return cliVersion >= minimumCLIVersion
    }

    public static func addArguments(machine: String) -> [String] {
        ["packages", "add", package, "--machine", machine, "--yes"]
    }

    public static func syncArguments(machine: String) -> [String] {
        ["sync", "--machine", machine, "--tags", package, "--yes"]
    }

    /// Every command Prepare runs, in order: the add only when the
    /// configuration does not ask for the package yet.
    public static func steps(machine: String, declared: Bool) -> [[String]] {
        (declared ? [] : [addArguments(machine: machine)]) + [syncArguments(machine: machine)]
    }

    /// What to run by hand when the CLI is too old for Prepare. A plain sync
    /// shows its plan and asks before it applies anything.
    public static func manualCommands(machine: String, declared: Bool) -> [String] {
        (declared ? [] : ["devmachine packages add \(package) --machine \(machine)"])
            + ["devmachine sync --machine \(machine)"]
    }

    /// An outdated package needs a newer packages release. The pin is shared
    /// by every machine, so the app explains it and never moves it itself.
    public static func outdatedCommands(machine: String) -> [String] {
        ["devmachine packages pin", "devmachine sync --machine \(machine)"]
    }

    /// The reason the CLI printed, from its last `error:` line.
    public static func failureCause(_ lines: [String]) -> String? {
        guard let line = lines.last(where: { $0.hasPrefix("error:") || $0.hasPrefix("Error:") }) else { return nil }
        let cause = line.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
        return cause.isEmpty ? nil : cause
    }
}
