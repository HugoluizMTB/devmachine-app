import Foundation

/// `devmachine update --cli-only`: the one CLI command the app runs to update
/// the CLI. It replaces the binary and nothing else, never the packages pin,
/// skills, doctor or sync. Plain `devmachine update` would touch those, so the
/// app never falls back to it.
public enum CLISelfUpdate {
    public static let arguments = ["update", "--cli-only"]

    /// The first CLI release that knows `--cli-only`.
    public static let minimumVersion = SemanticVersion(major: 0, minor: 7, patch: 23)

    public static func supportsCLIOnly(_ installed: SemanticVersion) -> Bool {
        installed >= minimumVersion
    }

    /// Cobra's own wording for a flag the installed CLI does not know.
    public static func isUnknownFlag(_ lines: [String]) -> Bool {
        lines.contains { $0.contains("unknown flag: --cli-only") }
    }

    /// The reason the CLI printed, from its last `error:` line.
    public static func failureCause(_ lines: [String]) -> String? {
        guard let line = lines.last(where: { $0.hasPrefix("error:") }) else { return nil }
        let cause = line.dropFirst("error:".count).trimmingCharacters(in: .whitespaces)
        return cause.isEmpty ? nil : cause
    }

    /// An app started from Finder gets launchd's short PATH, where the CLI
    /// would not find `brew` to upgrade a Homebrew install.
    public static func environment(base: [String: String]) -> [String: String] {
        var environment = base
        let path = base["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_COLOR"] = "1"
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// What the version re-read after the update says, or nil when it did not
    /// reach `expected`.
    public static func confirmedVersion(versionOutput: String, expected: SemanticVersion) -> SemanticVersion? {
        guard let version = SemanticVersion.first(in: versionOutput), version >= expected else { return nil }
        return version
    }
}
