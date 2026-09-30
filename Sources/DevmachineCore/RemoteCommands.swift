import Foundation

public enum RemoteCommands {
    public static let paneSentinel = "@@PANES@@"

    public static var onePasswordSocketPath: String {
        NSHomeDirectory() + "/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    }

    /// The one place the app's whole process reads and writes the SSH agent
    /// socket preference. `SettingsStore` (`DevmachineApp`) keeps it in sync on
    /// every change; everything that opens an ssh/mosh connection — including
    /// code in `DevmachineCore`, which cannot see `SettingsStore` — reads it
    /// here instead of each threading its own copy of the setting through.
    /// A lock guards it because ssh calls run off the main actor
    /// (`Task.detached`), while `SettingsStore` writes on the main actor.
    public final class SSHAgentSocketPreference: @unchecked Sendable {
        public static let shared = SSHAgentSocketPreference()

        private let lock = NSLock()
        private var value: String?

        public func current() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        public func update(_ newValue: String?) {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    /// Picks the ssh agent socket: an explicit override from Settings wins,
    /// then the 1Password agent if that socket file actually exists, then
    /// whatever this process inherited, and otherwise none. Forcing the
    /// 1Password path unconditionally broke everyone who does not run it — an
    /// app launched from the Dock inherits launchd's empty agent, not the
    /// shell's, which is why the fallback checks the process environment too.
    public static func sshAuthSocket(
        customSocket: String?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let customSocket, !customSocket.trimmingCharacters(in: .whitespaces).isEmpty {
            return customSocket
        }
        if fileExists(onePasswordSocketPath) {
            return onePasswordSocketPath
        }
        if let inherited = environment["SSH_AUTH_SOCK"], !inherited.isEmpty {
            return inherited
        }
        return nil
    }

    public static let listSessions =
        "tmux list-sessions -F '#S|#{session_windows}' 2>/dev/null"
        + "; echo '\(paneSentinel)'"
        + "; tmux list-panes -a -F '#S|#{pane_current_command}' 2>/dev/null"

    public static func attach(session: String) -> String {
        "tmux attach -t \(session)"
    }

    public static func newSession(name: String) -> String {
        "tmux new-session -A -s \(shellSingleQuoted(name))"
    }

    public static func sessionDirectory(session: String) -> String {
        "tmux display-message -p -t \(shellSingleQuoted(session)) '#{pane_current_path}'"
    }

    /// Creates the session up front, in a directory. Claude Code lists files
    /// for its `@` menu from the directory it starts in, and a session opened
    /// in a folder of many repositories gets no list at all, so where a session
    /// starts is a feature, not a detail.
    public static func createSession(name: String, directory: String) -> String {
        let trimmed = directory.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return "tmux new-session -d -s \(shellSingleQuoted(name))"
        }
        return "tmux new-session -d -s \(shellSingleQuoted(name)) -c \(remotePath(trimmed))"
    }

    /// A path for the remote shell. `~` is the shell's, so it stays outside the
    /// quotes as `$HOME`, and the rest is quoted as usual.
    static func remotePath(_ path: String) -> String {
        if path == "~" { return "\"$HOME\"" }
        if path.hasPrefix("~/") {
            return "\"$HOME\"/" + shellSingleQuoted(String(path.dropFirst(2)))
        }
        return shellSingleQuoted(path)
    }

    public static func rename(session: String, to newName: String) -> String {
        "tmux rename-session -t \(shellSingleQuoted(session)) \(shellSingleQuoted(newName))"
    }

    /// Asks tmux to draw the session again, without changing its size. Used
    /// when a pane returns to the screen unchanged, which otherwise gives the
    /// program inside no reason to repaint.
    public static func refreshClient(session: String) -> String {
        "tmux refresh-client -t \(shellSingleQuoted(session))"
    }

    public static func killSession(name: String) -> String {
        "tmux kill-session -t \(shellSingleQuoted(name))"
    }

    /// Moves to the folder a session is in, so a command reads what the person
    /// in that session sees.
    public static func inSessionDirectory(session: String, command: String) -> String {
        "cd \"$(tmux display -p -t \(shellSingleQuoted(session)) '#{pane_current_path}')\""
            + " && " + command
    }

    /// The same, for a folder that is already known — a session this Mac hosts,
    /// where there is no tmux to ask.
    public static func inDirectory(path: String, command: String) -> String {
        "cd \(shellSingleQuoted(path)) && " + command
    }

    // One round trip for the whole panel: the three git reads are joined by a
    // record separator, and `rev-parse` failing first is how "not a repo" is reported.
    public static let gitSnapshotBody =
        "git rev-parse --show-toplevel"
        + " && git status --porcelain=v2 --branch"
        + " && printf '\\x1e'"
        + " && git worktree list --porcelain"
        + " && printf '\\x1e'"
        + " && git log --format='%h%x1f%s%x1f%an%x1f%ar%x1f%D' -n 80"
        + " && printf '\\x1e'"
        + " && sh -c " + shellSingleQuoted(leftoverScan)

    // A remove that fails halfway drops git's record of the worktree but
    // leaves the folder. One that still holds a `.git` file pointing at the
    // dropped record is a leftover wherever it is; one with no `.git` at all
    // only inside the repository's own `.worktrees` folder, since beside
    // other worktrees it may be any unrelated project. `sh -c` because the
    // login shell may be zsh, which aborts on a glob that matches nothing.
    static let leftoverScan = """
        c=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
        w=${c%/.git}/.worktrees
        { git worktree list --porcelain | sed -n 's/^worktree //p' | sed 1d \\
            | while IFS= read -r x; do dirname -- "$x"; done
          printf '%s\\n' "$w"; } | sort -u | while IFS= read -r d; do
          for g in "$d"/*/; do
            g=${g%/}
            [ -d "$g" ] || continue
            if [ -f "$g/.git" ]; then
              t=$(sed -n 's/^gitdir: //p' "$g/.git" | head -n 1)
              case "$t" in "$c"/worktrees/*) [ -d "$t" ] || printf '%s\\n' "$g";; esac
            elif [ "$d" = "$w" ] && [ ! -e "$g/.git" ]; then
              printf '%s\\n' "$g"
            fi
          done
        done
        """

    public static func gitSnapshot(session: String) -> String {
        inSessionDirectory(session: session, command: gitSnapshotBody)
    }

    // The pane's cwd is the starting point, but the tree is rooted at the
    // repository so a session sitting in a subdirectory still shows the project.
    public static let fileTreeRootBody = "(git rev-parse --show-toplevel 2>/dev/null || pwd)"

    public static func fileTreeRoot(session: String) -> String {
        inSessionDirectory(session: session, command: fileTreeRootBody)
    }

    public static func listDirectory(path: String) -> String {
        "find \(shellSingleQuoted(path)) -mindepth 1 -maxdepth 1 -printf '%y\\t%f\\n' | sort -f"
    }

    /// The same listing where `find` has no `-printf`, which is every BSD
    /// system, this Mac included. `-p` marks a directory with a trailing
    /// slash, and that is the only type this tree needs to tell apart.
    public static func listDirectoryPortable(path: String) -> String {
        "ls -Ap1 -- \(shellSingleQuoted(path))"
    }

    /// Every file under the root, for the search field. Asks git first, which
    /// already knows the repository's files and skips what it ignores; a folder
    /// that is not a repository falls back to a walk that prunes the usual
    /// unsearchable trees. The cap keeps one wrong root from returning forever.
    public static func listFiles(root: String, limit: Int = 50_000) -> String {
        "cd \(remotePath(root)) && { git ls-files 2>/dev/null"
            + " || find . -type f -not -path './.git/*' -not -path '*/node_modules/*'"
            + " -not -path '*/.build/*' 2>/dev/null; } | head -n \(limit)"
    }

    /// Types text into a session without sending it, so a path can be put in a
    /// prompt that is already being written.
    public static func typeKeys(session: String, text: String) -> String {
        "tmux send-keys -t \(shellSingleQuoted(session)) -- \(shellSingleQuoted(text))"
    }

    /// `-l` keeps tmux from reading typed text such as `Up` or `C-c` as a key
    /// name; Return goes in a second, non-literal `send-keys`.
    public static func sendKeys(session: String, text: String) -> String {
        let target = shellSingleQuoted(session)
        return "tmux send-keys -t \(target) -l -- \(shellSingleQuoted(text)) \\; send-keys -t \(target) Enter"
    }

    public static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // ConnectTimeout bounds only the handshake; the keepalive is what kills a
    // poll whose remote command hangs after the connection is up.
    public static func sshBaseArgs(alias: String) -> [String] {
        [
            alias,
            "-o", "ConnectTimeout=5",
            "-o", "BatchMode=yes",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2"
        ]
    }

    public static func sshEnvironment(
        customSocket: String? = SSHAgentSocketPreference.shared.current(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var result = ["HOME": NSHomeDirectory()]
        if let socket = sshAuthSocket(customSocket: customSocket, fileExists: fileExists, environment: environment) {
            result["SSH_AUTH_SOCK"] = socket
        }
        return result
    }

    // Remote sessions do not report as xterm: the host's tmux gives every
    // `xterm*` client `extkeys`, then forwards the kitty keyboard protocol
    // that Claude Code enables, and SwiftTerm's kitty encoding breaks Enter
    // and dead keys. `tmux-256color` exists on both sides and keeps
    // bracketed paste, focus, RGB and cursor style.
    public static let remoteTerm = "tmux-256color"

    public static func terminalEnvironment(
        term: String = "xterm-256color",
        customSocket: String? = SSHAgentSocketPreference.shared.current(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var result = [
            "TERM=\(term)",
            "COLORTERM=truecolor",
            "HOME=\(NSHomeDirectory())",
            "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG=en_US.UTF-8"
        ]
        if let socket = sshAuthSocket(customSocket: customSocket, fileExists: fileExists, environment: environment) {
            result.append("SSH_AUTH_SOCK=\(socket)")
        }
        return result
    }
}
