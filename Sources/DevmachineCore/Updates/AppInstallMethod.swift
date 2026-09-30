import Foundation

public enum AppInstallMethod: Equatable, Sendable {
    case homebrew(brew: String)
    case manual
}

public enum HomebrewAppUpgrade {
    public static let displayCommand = "brew upgrade --cask devmachine-app"
    public static let arguments = ["upgrade", "--cask", "mydevmachine/tap/devmachine-app"]
}

/// A cask installs into `/Applications` and leaves a folder in its Caskroom.
/// A copy anywhere else was put there by hand, whatever Homebrew holds.
public struct AppInstallMethodDetector: Sendable {
    public static let caskPath = "/Applications/Devmachine.app"
    static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    static let caskrooms = ["/opt/homebrew/Caskroom/devmachine-app", "/usr/local/Caskroom/devmachine-app"]

    let bundlePath: String
    let fileExists: @Sendable (String) -> Bool
    let runner: any CommandRunner

    public init(
        bundlePath: String,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        runner: any CommandRunner = ProcessRunner()
    ) {
        self.bundlePath = bundlePath
        self.fileExists = fileExists
        self.runner = runner
    }

    public func detect() -> AppInstallMethod {
        guard URL(fileURLWithPath: bundlePath).standardizedFileURL.path == Self.caskPath,
              let brew = Self.brewPaths.first(where: fileExists)
        else { return .manual }
        if Self.caskrooms.contains(where: fileExists) { return .homebrew(brew: brew) }
        let listed = try? runner.runCapturing(
            executable: brew, args: ["list", "--cask", "devmachine-app"], environment: nil)
        return listed?.exitCode == 0 ? .homebrew(brew: brew) : .manual
    }
}
