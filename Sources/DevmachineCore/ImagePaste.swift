import Foundation

public struct ImageStoragePolicy: Equatable, Sendable {
    public let directory: String

    public init(directory: String) {
        self.directory = directory
    }

    public static let appManaged = ImageStoragePolicy(directory: ".cache/devmachine-app/images")
}

/// Pasting an image into a session that runs on another machine: the bytes go
/// to that machine's disk and the agent is given the path, because the agent
/// reads the clipboard of the machine it runs on, and a remote one has none.
public enum ImagePaste {
    /// Second-resolution time plus a random tail: two images pasted in the same
    /// second would otherwise overwrite each other.
    public static func fileName(date: Date, fileExtension: String, tail: String) -> String {
        let stamp = DateFormatter.pasteStamp.string(from: date)
        return "\(stamp)-\(tail).\(fileExtension)"
    }

    /// One round trip: make the directory, write what arrives on stdin, then
    /// print the absolute path. The agent needs an absolute path — `~` does not
    /// expand in its prompt, only in a shell.
    public static func writeCommand(fileName: String, policy: ImageStoragePolicy) -> String {
        let dir = "\"$HOME\"/\(policy.directory)"
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
