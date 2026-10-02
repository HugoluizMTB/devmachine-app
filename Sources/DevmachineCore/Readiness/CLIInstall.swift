import Foundation

/// How onboarding installs the devmachine CLI without a terminal. Homebrew
/// when this Mac has it, else the project's installer, which puts the binary
/// in `~/.local/bin` and needs no password or TTY.
public enum CLIInstallPlan: Equatable, Sendable {
    case homebrew(brew: String)
    case installer

    public static let tap = "mydevmachine/tap/devmachine"
    public static let installerURL = "https://mydevmachine.sh/install.sh"
    public static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    /// The release binary into `~/.local/bin`, never Homebrew: Homebrew
    /// refuses to install a tap formula on a Mac whose Xcode is behind.
    public static let noHomebrewCommand = "curl -fsSL \(installerURL) | DEVMACHINE_NO_BREW=1 sh"

    public static func choose(
        brewPaths: [String] = brewPaths, exists: (String) -> Bool
    ) -> CLIInstallPlan {
        brewPaths.first(where: exists).map { .homebrew(brew: $0) } ?? .installer
    }

    /// One shell line, so the trust step may fail on a Homebrew that has no
    /// `brew trust` without stopping the install, as the installer does.
    public var script: String {
        switch self {
        case let .homebrew(brew):
            let quoted = RemoteCommands.shellSingleQuoted(brew)
            return "\(quoted) trust --formula \(Self.tap) >/dev/null 2>&1 || true; "
                + "\(quoted) install \(Self.tap)"
        case .installer:
            return "curl -fsSL \(Self.installerURL) | sh"
        }
    }

    public var executable: String { "/bin/sh" }
    public var arguments: [String] { ["-c", script] }

    /// The same install, for a person who prefers to paste it.
    public var copyCommand: String {
        switch self {
        case .homebrew: return "brew install \(Self.tap)"
        case .installer: return "curl -fsSL \(Self.installerURL) | sh"
        }
    }

    /// Where the installer puts the binary when Homebrew is not used.
    public static func installerBinary(home: String) -> String {
        (home as NSString).appendingPathComponent(".local/bin/devmachine")
    }
}
