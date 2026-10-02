import Foundation

/// The shell a local pane runs: the one the account logs in with, the way
/// Terminal.app chooses it, so a pane brings the user's own configuration.
public enum LocalShell {
    public static let fallback = "/bin/zsh"

    public static func resolve(
        account: String?, environment: String?,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> String {
        [account, environment]
            .compactMap { $0 }
            .first { !$0.isEmpty && isExecutable($0) } ?? fallback
    }

    /// The account's login shell from the user database. `SHELL` is only the
    /// second choice: an app opened from Finder may not have it, or have a
    /// stale one.
    public static func current() -> String {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 4096)
        let found = getpwuid_r(getuid(), &entry, &buffer, buffer.count, &result) == 0 && result != nil
        let account = found ? String(cString: entry.pw_shell) : nil
        return resolve(account: account, environment: ProcessInfo.processInfo.environment["SHELL"])
    }
}

public enum ShellKind: Equatable, Sendable {
    case zsh, bash, fish, other

    public init(path: String) {
        switch (path as NSString).lastPathComponent {
        case "zsh": self = .zsh
        case "bash": self = .bash
        case "fish": self = .fish
        default: self = .other
        }
    }
}

/// How a local pane starts its shell, directly or inside the multiplexer.
public struct ShellLaunch: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let execName: String
    /// Added to the pane's environment.
    public let environment: [String]
    /// What the multiplexer runs instead of its own login `$SHELL`; empty
    /// leaves that default.
    public let multiplexerCommand: [String]
}

/// A program that dies without undoing its terminal modes (an ssh that drops,
/// an editor killed with SIGKILL) leaves mouse or focus reporting on, and every
/// mouse move then reaches the shell as typed text. No shell reads the mouse at
/// its own prompt, so the integration turns those modes off before each one.
public enum ShellIntegration {
    private static let reportingModes = [9, 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1015, 1016]

    public static let resetModes = reportingModes.map { "\u{1b}[?\($0)l" }.joined()
    static let resetModesLiteral = reportingModes.map { "\\033[?\($0)l" }.joined()

    static let zshPath = "zsh/.zshenv"
    static let bashPath = "bash/devmachine.bash"
    static let fishPath = "fish/devmachine.fish"

    /// zsh is started with `ZDOTDIR` on this folder so it reads this file
    /// first; the file puts `ZDOTDIR` back before zsh looks for the user's
    /// other startup files, so only the hook stays behind.
    static let zshenv = """
        unset ZDOTDIR
        [[ -r "$HOME/.zshenv" ]] && builtin source "$HOME/.zshenv"
        if [[ -o interactive ]]; then
          _devmachine_reset_terminal() {
            local last=$?
            builtin printf '\(resetModesLiteral)'
            return $last
          }
          precmd_functions+=(_devmachine_reset_terminal)
        fi

        """

    /// bash reads an init file only when it is not a login shell, so this one
    /// does a login shell's work itself: the login files in bash's own order,
    /// and `.bash_logout` on the way out.
    static let bash = """
        trap '[ -r "$HOME/.bash_logout" ] && . "$HOME/.bash_logout"' EXIT
        [ -r /etc/profile ] && . /etc/profile
        if [ -r "$HOME/.bash_profile" ]; then . "$HOME/.bash_profile"
        elif [ -r "$HOME/.bash_login" ]; then . "$HOME/.bash_login"
        elif [ -r "$HOME/.profile" ]; then . "$HOME/.profile"
        fi
        _devmachine_reset_terminal() {
          local last=$?
          builtin printf '\(resetModesLiteral)'
          return $last
        }
        PROMPT_COMMAND="_devmachine_reset_terminal${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

        """

    static let fish = """
        function _devmachine_reset_terminal --on-event fish_prompt
            builtin printf '\(resetModesLiteral)'
        end

        """

    public static let files: [String: String] = [zshPath: zshenv, bashPath: bash, fishPath: fish]

    /// Writes only what differs, so a pane start costs a few reads.
    public static func install(in directory: URL) throws {
        let fileManager = FileManager.default
        for (path, content) in files {
            let url = directory.appendingPathComponent(path)
            if (try? String(contentsOf: url, encoding: .utf8)) == content { continue }
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// `integrationDirectory` is nil when the files could not be written; the
    /// shell then starts plain rather than missing the user's configuration.
    public static func launch(shell: String, integrationDirectory: String?) -> ShellLaunch {
        let name = (shell as NSString).lastPathComponent
        let plain = ShellLaunch(
            executable: shell, arguments: [], execName: "-\(name)",
            environment: ["SHELL=\(shell)"], multiplexerCommand: [])
        guard let directory = integrationDirectory else { return plain }

        switch ShellKind(path: shell) {
        case .zsh:
            let zdotdir = (directory as NSString).appendingPathComponent("zsh")
            return ShellLaunch(
                executable: shell, arguments: [], execName: "-\(name)",
                environment: ["SHELL=\(shell)", "ZDOTDIR=\(zdotdir)"], multiplexerCommand: [])
        case .bash:
            let file = (directory as NSString).appendingPathComponent(bashPath)
            let arguments = ["--init-file", file, "-i"]
            return ShellLaunch(
                executable: shell, arguments: arguments, execName: name,
                environment: ["SHELL=\(shell)"], multiplexerCommand: [shell] + arguments)
        case .fish:
            let file = (directory as NSString).appendingPathComponent(fishPath)
            let quoted = "'" + file.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'") + "'"
            let arguments = ["-l", "-i", "-C", "source \(quoted)"]
            return ShellLaunch(
                executable: shell, arguments: arguments, execName: "-\(name)",
                environment: ["SHELL=\(shell)"], multiplexerCommand: [shell] + arguments)
        case .other:
            return plain
        }
    }
}
