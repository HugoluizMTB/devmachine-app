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

    public static func killSession(name: String) -> String {
        "tmux kill-session -t \(shellSingleQuoted(name))"
    }

    // One round trip for the whole panel: the three git reads are joined by a
    // record separator, and `rev-parse` failing first is how "not a repo" is reported.
    public static func gitSnapshot(session: String) -> String {
        "cd \"$(tmux display -p -t \(shellSingleQuoted(session)) '#{pane_current_path}')\""
            + " && git rev-parse --show-toplevel"
            + " && git status --porcelain=v2 --branch"
            + " && printf '\\x1e'"
            + " && git worktree list --porcelain"
            + " && printf '\\x1e'"
            + " && git log --format='%h%x1f%s%x1f%an%x1f%ar%x1f%D' -n 80"
    }

    // The pane's cwd is the starting point, but the tree is rooted at the
    // repository so a session sitting in a subdirectory still shows the project.
    public static func fileTreeRoot(session: String) -> String {
        "cd \"$(tmux display -p -t \(shellSingleQuoted(session)) '#{pane_current_path}')\""
            + " && (git rev-parse --show-toplevel 2>/dev/null || pwd)"
    }

    public static func listDirectory(path: String) -> String {
        "find \(shellSingleQuoted(path)) -mindepth 1 -maxdepth 1 -printf '%y\\t%f\\n' | sort -f"
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
