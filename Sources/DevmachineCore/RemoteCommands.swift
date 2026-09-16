import Foundation

public enum RemoteCommands {
    public static let paneSentinel = "@@PANES@@"

    public static let statsSnapshot =
        "echo '@@MEM@@'; free -b | awk 'NR==2{print $2, $3, $7}'"
        + "; echo '@@SWAP@@'; free -b | awk 'NR==3{print $2, $3}'"
        + "; echo '@@DISK@@'; df -B1 --output=used,avail,pcent / | tail -1"
        + "; echo '@@LOAD@@'; cat /proc/loadavg"
        + "; echo '@@DOCKER@@'; docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}|{{.CPUPerc}}'"
        + "; echo '@@USERS@@'; ps -eo user=,rss= | awk '{a[$1]+=$2} END{for (u in a) print u, a[u]}'"

    public static var onePasswordSocketPath: String {
        NSHomeDirectory() + "/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
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

    public static func sendKeys(session: String, text: String) -> String {
        "tmux send-keys -t \(shellSingleQuoted(session)) -- \(shellSingleQuoted(text)) Enter"
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

    public static func sshEnvironment() -> [String: String] {
        [
            "SSH_AUTH_SOCK": onePasswordSocketPath,
            "HOME": NSHomeDirectory()
        ]
    }

    // Remote sessions do not report as xterm: the host's tmux gives every
    // `xterm*` client `extkeys`, then forwards the kitty keyboard protocol
    // that Claude Code enables, and SwiftTerm's kitty encoding breaks Enter
    // and dead keys. `tmux-256color` exists on both sides and keeps
    // bracketed paste, focus, RGB and cursor style.
    public static let remoteTerm = "tmux-256color"

    public static func terminalEnvironment(term: String = "xterm-256color") -> [String] {
        [
            "TERM=\(term)",
            "COLORTERM=truecolor",
            "HOME=\(NSHomeDirectory())",
            "SSH_AUTH_SOCK=\(onePasswordSocketPath)",
            "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG=en_US.UTF-8"
        ]
    }
}
