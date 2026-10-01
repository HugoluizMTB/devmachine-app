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

/// Moving files between this Mac and a workspace goes through the CLI, which
/// owns the transfer rules: never overwrite, folders as one archive, names
/// never read as shell syntax. The app only builds the arguments and reads
/// the JSON back.
public enum FileTransfer {
    public static let downloadCommand = "download"
    public static let folderExtension = ".tar.gz"

    /// Every path follows `--`, so a file called `-rf` stays a path.
    public static func downloadArguments(paths: [String], workspace: String, to directory: String) -> [String] {
        ["--format", "json", "download", "--workspace", workspace, "--to", directory, "--"] + paths
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
