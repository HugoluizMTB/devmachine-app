import Foundation

/// One provider as `dns providers` reports it: the zones its token can see,
/// or why it could not ask.
public struct DNSProviderAnswer: Codable, Equatable, Sendable {
    public let name: String
    public let zones: [String]
    public let error: String?

    public init(name: String, zones: [String], error: String?) {
        self.name = name
        self.zones = zones
        self.error = error
    }

    /// A provider that failed comes back with `"zones": null`; that row must
    /// not fail the whole answer.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        zones = try c.decodeIfPresent([String].self, forKey: .zones) ?? []
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    public var isAnswering: Bool { error == nil && !zones.isEmpty }
}

/// The step of the setup that is running or failed.
public enum DNSSetupStep: Equatable, Sendable {
    case install
    case saveToken
    case sync
}

/// What the person started from the card. `finished` keeps nothing on
/// screen by itself: the next `dns providers` answer decides.
public enum DNSSetupJob: Equatable, Sendable {
    case running(DNSSetupStep)
    case failed(DNSSetupStep, cause: String, details: String)
    case finished
}

/// Why a provider in the configuration does not answer yet.
public enum DNSSetupProblem: Equatable, Sendable {
    /// In the configuration, never applied by a sync.
    case notApplied
    /// Applied, but its call failed: most often a token never pushed.
    case providerError(String)
    /// Applied and answering, with no zone it may manage.
    case noZones
}

/// Whether the selected machine can write DNS records. Anything short of
/// `ready` means `expose add` only prints the record to create by hand.
public enum DNSSetupState: Equatable, Sendable {
    /// Nothing read, or the machine could not be asked: no card.
    case unknown
    case ready
    case noneInstalled
    case notSynced(provider: String, problem: DNSSetupProblem)
    case working(DNSSetupStep)
    case failed(DNSSetupStep, cause: String, details: String)

    public var showsCard: Bool {
        self != .unknown && self != .ready
    }
}

public enum DNSProviderSetup {
    /// `declared` is the DNS packages the configuration asks for on the
    /// machine (`packages list`), `answers` what `dns providers` said (it
    /// lists only what a sync applied). A nil input is one that could not be
    /// read. Only a provider answering with a zone makes the machine ready.
    public static func evaluate(
        declared: [String]?, answers: [DNSProviderAnswer]?, job: DNSSetupJob?
    ) -> DNSSetupState {
        if case .running(let step) = job { return .working(step) }
        if answers?.contains(where: \.isAnswering) == true { return .ready }
        if case let .failed(step, cause, details) = job { return .failed(step, cause: cause, details: details) }
        if declared == nil && answers == nil { return .unknown }

        let applied = answers?.map(\.name) ?? []
        let candidates = applied + (declared ?? []).filter { !applied.contains($0) }
        guard let provider = candidates.first else { return .noneInstalled }
        guard let answers else { return .unknown }
        guard let answer = answers.first(where: { $0.name == provider }) else {
            return .notSynced(provider: provider, problem: .notApplied)
        }
        if let error = answer.error { return .notSynced(provider: provider, problem: .providerError(error)) }
        return .notSynced(provider: provider, problem: .noZones)
    }

    /// Edits the configuration on this Mac only; no machine is touched.
    public static func addArguments(package: String, machine: String) -> [String] {
        ["packages", "add", package, "--machine", machine, "--yes"]
    }

    /// The value never goes in the arguments, where `ps` and logs would see
    /// it: it is written to the command's standard input.
    public static func secretArguments(credential: String) -> [String] {
        ["secrets", "set", credential, "--stdin"]
    }

    /// The CLI reads one line. A value that is empty, or that holds a line
    /// break inside, would be stored cut short, so it is refused here.
    public static func secretInput(_ value: String) -> Data? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return nil }
        return Data((trimmed + "\n").utf8)
    }

    /// `--tags` applies the provider alone, never everything else waiting
    /// in the configuration; the push then delivers its token, which the
    /// sync created the place for.
    public static func syncSteps(package: String, machine: String) -> [[String]] {
        [
            ["sync", "--machine", machine, "--tags", package, "--yes"],
            ["credentials", "push", "--machine", machine, "--yes"],
        ]
    }

    /// The same steps for a terminal, for a CLI too old to run them from here.
    /// A plain sync shows its plan and asks before it applies anything.
    public static func manualCommands(package: String, machine: String, declared: Bool) -> [String] {
        (declared ? [] : ["devmachine packages add \(package) --machine \(machine)"]) + [
            "devmachine secrets set \(package)",
            "devmachine sync --machine \(machine)",
            "devmachine credentials push --machine \(machine)",
        ]
    }
}

/// Which packages are DNS providers, and what each one needs beyond a token.
public enum DNSProviderCatalog {
    /// `packages list` does not report a package's kind yet; until it does,
    /// the provider packages' own summary ("DNS zones on …") decides.
    public static func isProvider(kind: String?, category: String?, summary: String?) -> Bool {
        if kind != nil || category != nil {
            return kind?.lowercased() == "dns" || category?.lowercased() == "dns"
        }
        return summary?.hasPrefix("DNS zones") ?? false
    }

    /// Hostinger's token may lack the Domains portfolio permission; it then
    /// sees no zone unless the machine's settings list them.
    private static let zonesSettings = ["hostinger": "hostinger.zones"]

    public static func zonesSetting(for package: String) -> String? {
        zonesSettings[package]
    }

    /// The machine setting to add to `config.yml` by hand: the CLI has no
    /// command that sets a machine's setting.
    public static func zonesSnippet(package: String, machine: String, zones: String) -> String? {
        guard let setting = zonesSetting(for: package) else { return nil }
        let names = zones.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let list = (names.isEmpty ? ["example.com"] : names).joined(separator: ", ")
        return """
            machines:
              - name: \(machine)
                settings:
                  \(setting): [\(list)]
            """
    }
}
