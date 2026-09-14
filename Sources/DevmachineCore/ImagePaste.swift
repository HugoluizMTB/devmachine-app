import Foundation

/// Pasting an image into a session that runs on another machine: the bytes go
/// to that machine's disk and the agent is given the path, because the agent
/// reads the clipboard of the machine it runs on, and a remote one has none.
public enum ImagePaste {
    /// Claude Code's own directory for attached images. It sweeps this on its
    /// own, so the app never needs a cleanup task. An agent that keeps images
    /// somewhere else gets another constant here, and nothing else changes.
    public static let directory = ".claude/image-cache/devmachine-app"

    /// Second-resolution time plus a random tail: two images pasted in the same
    /// second would otherwise overwrite each other.
    public static func fileName(date: Date, fileExtension: String, tail: String) -> String {
        let stamp = DateFormatter.pasteStamp.string(from: date)
        return "\(stamp)-\(tail).\(fileExtension)"
    }

    /// One round trip: make the directory, write what arrives on stdin, then
    /// print the absolute path. The agent needs an absolute path — `~` does not
    /// expand in its prompt, only in a shell.
    public static func writeCommand(fileName: String) -> String {
        let dir = "\"$HOME\"/\(directory)"
        let file = "\(dir)/\(shellSingleQuoted(fileName))"
        return "mkdir -p \(dir) && cat > \(file) && printf '%s\\n' \(file)"
    }

    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension DateFormatter {
    static let pasteStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
