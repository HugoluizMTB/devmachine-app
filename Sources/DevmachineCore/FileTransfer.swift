import Foundation

/// One line of `devmachine --format json download`.
public struct DownloadedFile: Decodable, Equatable, Sendable {
    public let remote: String
    public let local: String?
    public let bytes: Int64
    public let folder: Bool
    public let error: String?

    public init(remote: String, local: String?, bytes: Int64, folder: Bool, error: String?) {
        self.remote = remote
        self.local = local
        self.bytes = bytes
        self.folder = folder
        self.error = error
    }
}

/// One line of `devmachine --format json upload`.
public struct UploadedFile: Decodable, Equatable, Sendable {
    public let local: String
    public let remote: String?
    public let bytes: Int64
    public let error: String?

    public init(local: String, remote: String?, bytes: Int64, error: String?) {
        self.local = local
        self.remote = remote
        self.bytes = bytes
        self.error = error
    }
}

/// One line of `devmachine download --progress`, on stderr: the bytes of one
/// path so far. A folder's total is 0, since its archive is packed as it
/// travels and has no size until it ends.
public struct DownloadProgress: Decodable, Equatable, Sendable {
    public let remote: String
    public let done: Int64
    public let total: Int64

    public init(remote: String, done: Int64, total: Int64) {
        self.remote = remote
        self.done = done
        self.total = total
    }
}

/// Every path of one download, added up. The CLI sizes every path before the
/// first byte moves, so the total is whole from the first lines on.
public struct DownloadTally: Equatable, Sendable {
    private var files: [String: DownloadProgress] = [:]

    public init() {}

    public mutating func record(_ progress: DownloadProgress) {
        files[progress.remote] = progress
    }

    public var done: Int64 {
        files.values.reduce(0) { $0 + $1.done }
    }

    /// Nil before the first line and while a folder is among the paths.
    public var total: Int64? {
        guard !files.isEmpty, files.values.allSatisfy({ $0.total > 0 }) else { return nil }
        return files.values.reduce(0) { $0 + $1.total }
    }
}

/// Moving files between this Mac and a workspace goes through the CLI, which
/// owns the transfer rules: never overwrite, folders as one archive, names
/// never read as shell syntax. The app only builds the arguments and reads
/// the JSON back.
public enum FileTransfer {
    public static let downloadCommand = "download"
    public static let folderExtension = ".tar.gz"

    public static let progressFlag = "--progress"

    /// Every path follows `--`, so a file called `-rf` stays a path.
    public static func downloadArguments(
        paths: [String], workspace: String, to directory: String, progress: Bool = false
    ) -> [String] {
        ["--format", "json", "download", "--workspace", workspace, "--to", directory]
            + (progress ? [progressFlag] : []) + ["--"] + paths
    }

    public static func uploadArguments(files: [String], workspace: String, directory: String) -> [String] {
        ["--format", "json", "upload", "--workspace", workspace, "--dir", directory, "--"] + files
    }

    /// The CLI prints its JSON even when some paths failed, and exits non-zero;
    /// the per-path errors are in the entries.
    public static func parseDownloads(_ stdout: String) -> [DownloadedFile]? {
        try? JSONDecoder().decode([DownloadedFile].self, from: Data(stdout.utf8))
    }

    public static func parseUploads(_ stdout: String) -> [UploadedFile]? {
        try? JSONDecoder().decode([UploadedFile].self, from: Data(stdout.utf8))
    }

    /// An installed CLI older than the command answers with Cobra's own words.
    public static func isUnknownCommand(_ stderr: String, _ command: String) -> Bool {
        stderr.contains("unknown command \"\(command)\"")
    }

    /// A CLI older than a flag refuses the whole command before it connects.
    public static func isUnknownFlag(_ stderr: String, _ flag: String) -> Bool {
        stderr.contains("unknown flag: \(flag)")
    }

    public static func parseProgress(_ line: String) -> DownloadProgress? {
        try? JSONDecoder().decode(DownloadProgress.self, from: Data(line.utf8))
    }

    /// stderr as an error message: the progress lines are for the bar.
    public static func withoutProgress(_ stderr: String) -> String {
        stderr.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { parseProgress(String($0)) == nil }
            .joined(separator: "\n")
    }

    public static func displayPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// The name a file takes when it lands next to others: `-2`, `-3` and so
    /// on before the extension, the same counter the CLI uses.
    public static func numbered(_ name: String, _ n: Int) -> String {
        guard n >= 2 else { return name }
        var stem = name
        var ext = ""
        if name.hasSuffix(folderExtension), name.count > folderExtension.count {
            stem = String(name.dropLast(folderExtension.count))
            ext = folderExtension
        } else if let dot = name.lastIndex(of: "."), dot != name.startIndex,
                  name.index(after: dot) != name.endIndex {
            stem = String(name[..<dot])
            ext = String(name[dot...])
        }
        return "\(stem)-\(n)\(ext)"
    }

    public static func freeName(_ name: String, taken: (String) -> Bool) -> String {
        var n = 1
        while taken(numbered(name, n)) { n += 1 }
        return numbered(name, n)
    }

    /// The name a drag shows before the bytes exist: a folder arrives as one
    /// archive.
    public static func promisedName(of path: String, isDirectory: Bool) -> String {
        let name = (path as NSString).lastPathComponent
        return isDirectory ? name + folderExtension : name
    }
}
