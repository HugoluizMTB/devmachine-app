import Foundation

public enum CLIInstallMethod: Equatable, Sendable {
    case homebrew
    case script
}

public struct CLIUpdateNotice: Equatable, Sendable {
    public let installed: SemanticVersion
    public let latest: SemanticVersion
    public let command: String
    public let releaseURL: URL?

    public init(installed: SemanticVersion, latest: SemanticVersion, command: String, releaseURL: URL?) {
        self.installed = installed
        self.latest = latest
        self.command = command
        self.releaseURL = releaseURL
    }
}

/// The app only ever shows this command. The person runs it: upgrading the
/// CLI is their call, and the app never types into a session for them.
public enum CLIUpdateAdvice {
    static let homebrewPrefixes = ["/opt/homebrew/", "/home/linuxbrew/.linuxbrew/"]

    /// `resolvedPath` is the executable with symlinks followed: Homebrew on
    /// Intel links `/usr/local/bin/devmachine` into its Cellar, while the
    /// install script puts a plain file in the same folder.
    public static func installMethod(resolvedPath: String) -> CLIInstallMethod {
        if resolvedPath.contains("/Cellar/") || homebrewPrefixes.contains(where: resolvedPath.hasPrefix) {
            return .homebrew
        }
        return .script
    }

    public static func command(for method: CLIInstallMethod) -> String {
        switch method {
        case .homebrew: return "brew upgrade devmachine"
        case .script: return "curl -fsSL https://mydevmachine.sh/install.sh | sh"
        }
    }

    public static func notice(
        versionOutput: String, latest: GitHubRelease, method: CLIInstallMethod
    ) -> CLIUpdateNotice? {
        guard let installed = SemanticVersion.first(in: versionOutput),
              case .available = UpdatePolicy.evaluate(current: installed, release: latest, skippedVersion: nil),
              let version = latest.version
        else { return nil }
        return CLIUpdateNotice(
            installed: installed, latest: version, command: command(for: method), releaseURL: latest.htmlURL)
    }
}
