import Foundation

/// What a file turns out to be once it is read, and what the viewer should do
/// with it.
public enum FilePreviewKind: Equatable, Sendable {
    case code(language: String?)
    case markdown
    case text
    case image
    case binary
    case tooLarge(bytes: Int)
}

public struct FilePreview: Equatable, Sendable {
    public let path: String
    public let kind: FilePreviewKind
    public let text: String?
    public let data: Data?
    public let byteCount: Int
    /// The file is longer than what was read, so the viewer says so instead of
    /// letting someone believe they are at the end of it.
    public let isTruncated: Bool

    public init(
        path: String, kind: FilePreviewKind, text: String?, data: Data?,
        byteCount: Int, isTruncated: Bool
    ) {
        self.path = path
        self.kind = kind
        self.text = text
        self.data = data
        self.byteCount = byteCount
        self.isTruncated = isTruncated
    }

    public var name: String { (path as NSString).lastPathComponent }
}

public enum FilePreviewReader {
    /// Read at most this much of a file. Two megabytes of text is already more
    /// than anyone reads in a viewer, and the whole payload crosses as base64.
    public static let byteLimit = 2_000_000

    /// Beyond this, highlighting a string blocks the interface long enough to
    /// feel broken, so the text is shown plain.
    public static let highlightLimit = 200_000

    public static let imageLimit = 5_000_000

    /// Size first, then the bytes, with a record separator between them.
    /// `base64` wraps its output on both systems, hence the `tr`.
    public static func command(path: String, limit: Int = byteLimit) -> String {
        let quoted = RemoteCommands.shellSingleQuoted(path)
        return "{ wc -c < \(quoted) | tr -d ' '; printf '\\036';"
            + " head -c \(limit) -- \(quoted) | base64 | tr -d '\\n'; }"
    }

    /// Turns the command's output into something the viewer can show. Returns
    /// nil when the output is not the shape the command produces, which is what
    /// a failed read looks like.
    public static func parse(_ output: String, path: String, limit: Int = byteLimit)
        -> FilePreview? {
        let parts = output.split(separator: "\u{1e}", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let byteCount = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }

        let payload = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
            return nil
        }
        let truncated = byteCount > data.count

        if isImage(path) {
            guard byteCount <= imageLimit else {
                return FilePreview(
                    path: path, kind: .tooLarge(bytes: byteCount), text: nil, data: nil,
                    byteCount: byteCount, isTruncated: truncated)
            }
            return FilePreview(
                path: path, kind: .image, text: nil, data: data,
                byteCount: byteCount, isTruncated: truncated)
        }

        guard byteCount <= limit || !truncated || looksLikeText(data) else {
            return FilePreview(
                path: path, kind: .tooLarge(bytes: byteCount), text: nil, data: nil,
                byteCount: byteCount, isTruncated: truncated)
        }

        guard looksLikeText(data), let text = String(data: data, encoding: .utf8) else {
            return FilePreview(
                path: path, kind: .binary, text: nil, data: data,
                byteCount: byteCount, isTruncated: truncated)
        }

        return FilePreview(
            path: path, kind: kind(for: path, text: text), text: text, data: data,
            byteCount: byteCount, isTruncated: truncated)
    }

    /// A NUL byte is the oldest and still the most reliable sign that a file is
    /// not text.
    public static func looksLikeText(_ data: Data) -> Bool {
        !data.prefix(8_000).contains(0)
    }

    static func kind(for path: String, text: String) -> FilePreviewKind {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "md" || ext == "markdown" { return .markdown }
        if text.utf8.count > highlightLimit { return .text }
        if let language = language(for: path) { return .code(language: language) }
        return .text
    }

    public static func isImage(_ path: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]
            .contains((path as NSString).pathExtension.lowercased())
    }

    /// The language highlight.js knows this file by. A name it does not know is
    /// worse than none: it highlights nothing and reports an error.
    public static func language(for path: String) -> String? {
        let name = (path as NSString).lastPathComponent.lowercased()
        if let byName = namedFiles[name] { return byName }
        return extensions[(path as NSString).pathExtension.lowercased()]
    }

    static let namedFiles: [String: String] = [
        "dockerfile": "dockerfile", "makefile": "makefile", "rakefile": "ruby",
        "gemfile": "ruby", "podfile": "ruby", "package.json": "json",
        "cargo.toml": "toml", "caddyfile": "nginx",
    ]

    static let extensions: [String: String] = [
        "swift": "swift", "m": "objectivec", "mm": "objectivec", "h": "objectivec",
        "c": "c", "cc": "cpp", "cpp": "cpp", "hpp": "cpp", "rs": "rust", "go": "go",
        "py": "python", "rb": "ruby", "js": "javascript", "mjs": "javascript",
        "cjs": "javascript", "jsx": "javascript", "ts": "typescript", "tsx": "typescript",
        "java": "java", "kt": "kotlin", "kts": "kotlin", "php": "php", "cs": "csharp",
        "scala": "scala", "lua": "lua", "pl": "perl", "r": "r", "ex": "elixir",
        "exs": "elixir", "erl": "erlang", "hs": "haskell", "dart": "dart",
        "sh": "bash", "bash": "bash", "zsh": "bash", "fish": "bash",
        "json": "json", "yml": "yaml", "yaml": "yaml", "toml": "toml", "ini": "ini",
        "conf": "ini", "xml": "xml", "html": "xml", "htm": "xml", "svg": "xml",
        "css": "css", "scss": "scss", "less": "less", "sql": "sql", "graphql": "graphql",
        "diff": "diff", "patch": "diff", "tf": "terraform", "proto": "protobuf",
        "vim": "vim", "el": "lisp", "clj": "clojure", "ps1": "powershell",
    ]
}
