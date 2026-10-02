import Foundation

/// The multiplexer the app carries for local sessions. It holds the shell in a
/// process of its own, so a session outlives the app the way a remote tmux
/// session outlives the connection.
public enum Zmx {
    /// Where the session sockets live. Set explicitly, never left to `TMPDIR`:
    /// the value differs between a launchd-started app and a shell, which would
    /// split one set of sessions into two invisible namespaces. It is also kept
    /// short, because a unix socket path cannot exceed 103 bytes.
    public static func socketDirectory(uid: uid_t = getuid()) -> String {
        "/tmp/zmx-\(uid)"
    }

    public static let socketPathLimit = 103

    /// Room left for a session name inside the socket path, with a little
    /// slack: the path is the directory, a separator, and the name.
    public static func nameLimit(socketDirectory: String) -> Int {
        max(1, socketPathLimit - socketDirectory.utf8.count - 1 - 2)
    }

    /// A name the multiplexer accepts: no separator, no empty, no dot entries,
    /// and short enough for the socket path.
    public static func sessionName(from raw: String, socketDirectory: String) -> String {
        var cleaned = raw.map { ch -> Character in
            ch == "/" || ch == "\0" || ch == "\t" || ch == "\n" ? "-" : ch
        }
        while cleaned.first == "." { cleaned.removeFirst() }
        var name = String(cleaned).trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "shell" }
        let limit = nameLimit(socketDirectory: socketDirectory)
        while name.utf8.count > limit { name.removeLast() }
        return name.isEmpty ? "s" : name
    }

    /// The command runs only when the session is created; attaching to one
    /// that exists reaches the shell already in it.
    public static func attachArguments(name: String, command: [String] = []) -> [String] {
        ["attach", name] + command
    }
    public static let listArguments = ["ls"]
    public static func killArguments(name: String) -> [String] { ["kill", name] }

    /// Raw input for a session, as if it were typed. There is no trailing
    /// newline, so text lands in a prompt without running it.
    public static func sendArguments(name: String, text: String) -> [String] {
        ["send", name, text]
    }

    /// The carriage return a terminal sends for Return; `\n` reaches some
    /// programs as a line feed instead, which is not the same key.
    public static let enterText = "\r"

    /// The session's shell, from a listing, so the program running in it can be
    /// asked to repaint.
    public static func pid(of session: String, in listing: String) -> Int? {
        ZmxListParser.parse(listing).first { $0.name == session }?.pid
    }

    /// `HOME` because a shell other than zsh does not look it up when it is
    /// missing, and then never finds the user's startup files. `SHELL` comes
    /// from the shell's own launch. The detach key is off because the app's
    /// own UI decides when a pane detaches, and the default binding would
    /// swallow the quit signal instead.
    public static func environment(
        socketDirectory: String = Zmx.socketDirectory(), home: String = NSHomeDirectory(),
        term: String = "xterm-256color"
    ) -> [String] {
        ["TERM=\(term)", "HOME=\(home)", "ZMX_DIR=\(socketDirectory)", "ZMX_NO_DETACH_KEY=1",
         "LANG=en_US.UTF-8", "COLORTERM=truecolor"]
    }
}

/// One line of the multiplexer's session list.
public struct ZmxSession: Equatable, Sendable {
    public let name: String
    public let pid: Int
    public let clients: Int
    public let directory: String?

    public init(name: String, pid: Int, clients: Int, directory: String?) {
        self.name = name
        self.pid = pid
        self.clients = clients
        self.directory = directory
    }
}

public enum ZmxListParser {
    /// Tab-separated `key=value` pairs, one session per line. A line that
    /// carries an error instead of a pid is skipped: it names a session that is
    /// being cleaned up or cannot be reached, not one to show.
    public static func parse(_ output: String) -> [ZmxSession] {
        output.split(separator: "\n").compactMap { rawLine in
            var fields: [String: String] = [:]
            for field in rawLine.split(separator: "\t") {
                guard let split = field.firstIndex(of: "=") else { continue }
                // The current session is marked with an arrow before the first
                // key, so the marker has to come off the key, not the value.
                let key = field[field.startIndex..<split]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\u{2192} "))
                fields[key] = String(field[field.index(after: split)...])
            }
            guard let name = fields["name"], !name.isEmpty,
                  let pid = fields["pid"].flatMap(Int.init)
            else { return nil }
            return ZmxSession(
                name: name,
                pid: pid,
                clients: fields["clients"].flatMap(Int.init) ?? 0,
                directory: fields["cwd"].map(directoryPath))
        }
    }

    /// The directory arrives as a URI when the shell reports it: strip the
    /// scheme and host so the value is a path like every other one in the app.
    static func directoryPath(_ value: String) -> String {
        guard value.hasPrefix("file://") else { return value }
        let rest = value.dropFirst("file://".count)
        guard let slash = rest.firstIndex(of: "/") else { return String(rest) }
        return String(rest[slash...]).removingPercentEncoding ?? String(rest[slash...])
    }
}
