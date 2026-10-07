import Foundation

/// What this app build needs from the CLI and the packages release to draw
/// Home. Released in this order: CLI, packages, app.
public struct WidgetAppManifest: Equatable, Sendable {
    public let engine: String
    public let requiresCLI: SemanticVersion
    public let requiresPackagesTag: String

    public init(engine: String, requiresCLI: SemanticVersion, requiresPackagesTag: String) {
        self.engine = engine
        self.requiresCLI = requiresCLI
        self.requiresPackagesTag = requiresPackagesTag
    }

    public var requiresPackages: PackagesVersion? { PackagesVersion(requiresPackagesTag) }

    public static let current = WidgetAppManifest(
        engine: WidgetContract.current.engine,
        requiresCLI: SemanticVersion(major: 0, minor: 9, patch: 0),
        requiresPackagesTag: "v39")
}

public struct CompatibilityGap: Equatable, Sendable {
    public let cliBehind: Bool
    public let packagesBehind: Bool
    public let installedCLI: SemanticVersion?
    public let pinnedPackages: String?
    public let command: CLIUpdateCommand

    public init(
        cliBehind: Bool, packagesBehind: Bool, installedCLI: SemanticVersion?, pinnedPackages: String?,
        command: CLIUpdateCommand
    ) {
        self.cliBehind = cliBehind
        self.packagesBehind = packagesBehind
        self.installedCLI = installedCLI
        self.pinnedPackages = pinnedPackages
        self.command = command
    }
}

public enum CompatibilityStatus: Equatable, Sendable {
    case ok
    case unknown
    case newerAvailable
    case behind(CompatibilityGap)
}

public enum CompatibilityCheck {
    public static func evaluate(
        manifest: WidgetAppManifest, cliVersionOutput: String?, packages: PackagesOutdated?
    ) -> CompatibilityStatus {
        let cli = cliVersionOutput.flatMap { SemanticVersion.first(in: $0) }
        let pinnedTag = packages?.pinned.trimmingCharacters(in: .whitespaces)
        let pinned = pinnedTag.flatMap { $0.isEmpty ? nil : PackagesVersion($0) }
        guard cli != nil || pinned != nil else { return .unknown }
        let cliBehind = cli.map { $0 < manifest.requiresCLI } ?? false
        let packagesBehind = pinned.flatMap { pin in manifest.requiresPackages.map { pin < $0 } } ?? false
        if cliBehind || packagesBehind {
            let supportsNoMachines = cli.map { $0 >= CLIUpdateCommand.noMachinesVersion } ?? true
            let command: CLIUpdateCommand = packagesBehind && supportsNoMachines ? .noMachines : .cliOnly
            return .behind(CompatibilityGap(
                cliBehind: cliBehind, packagesBehind: packagesBehind, installedCLI: cli,
                pinnedPackages: pinned == nil ? nil : pinnedTag, command: command))
        }
        return packages?.newer == true ? .newerAvailable : .ok
    }
}

public enum CompatibilityCopy {
    public static func title(_ gap: CompatibilityGap) -> String {
        switch (gap.cliBehind, gap.packagesBehind) {
        case (true, true): return "Home widgets need a newer CLI and packages"
        case (true, false): return "Home widgets need a newer devmachine CLI"
        default: return "Home widgets need a newer packages release"
        }
    }

    public static func note(_ gap: CompatibilityGap, manifest: WidgetAppManifest) -> String {
        let cli = gap.installedCLI?.description ?? "an unknown version"
        let packages = gap.pinnedPackages ?? "an unknown release"
        return "This app needs CLI \(manifest.requiresCLI) and packages \(manifest.requiresPackagesTag) or newer. "
            + "You have CLI \(cli) and packages \(packages)."
    }
}

extension CLIUpdateCommand {
    /// What a person would type; the app runs `arguments`.
    public var commandLine: String {
        switch self {
        case .cliOnly: return "devmachine update --cli-only"
        case .noMachines: return "devmachine update --no-machines"
        case .packagesOnly: return "devmachine update --no-machines --skip-cli"
        }
    }
}
