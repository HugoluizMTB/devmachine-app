import Foundation

/// What a link in a terminal opens. The text on screen comes from somewhere
/// else, so a link is data: only the schemes a browser or a mail client answers
/// are opened, and a bare path is opened only when it names a file that exists
/// here.
public enum TerminalLink {
    public enum Target: Equatable {
        case web(URL)
        case file(String)

        /// What "copy link" puts on the clipboard.
        public var text: String {
            switch self {
            case let .web(url): return url.absoluteString
            case let .file(path): return path
            }
        }
    }

    public static let allowedSchemes: Set<String> = ["http", "https", "mailto", "ftp", "ftps"]

    /// - Parameters:
    ///   - folder: the session's own folder, for a relative path. A session on
    ///     another machine has none: its paths do not name files on this Mac.
    public static func target(
        for raw: String, folder: String?,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Target? {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return nil }
        if let url = URL(string: link), let scheme = url.scheme?.lowercased() {
            if scheme == "file" {
                return fileTarget(url.path, folder: nil, exists: exists)
            }
            // An unknown scheme is not refused outright: "App.swift:12" parses
            // as one, and a file location is the other thing a terminal prints.
            if allowedSchemes.contains(scheme) { return .web(url) }
        }
        return fileTarget(link, folder: folder, exists: exists)
    }

    /// The compiler, the test runner and the linter all print `file:line` or
    /// `file:line:column`; the file is what the Mac can open.
    static func stripLocation(_ path: String) -> String {
        guard let range = path.range(of: #":[0-9]+(?::[0-9]+)?$"#, options: .regularExpression)
        else { return path }
        return String(path[..<range.lowerBound])
    }

    private static func fileTarget(
        _ raw: String, folder: String?, exists: (String) -> Bool
    ) -> Target? {
        for candidate in [raw, stripLocation(raw)] {
            let expanded = NSString(string: candidate).expandingTildeInPath
            let path = expanded.hasPrefix("/")
                ? expanded
                : folder.map { URL(fileURLWithPath: $0).appendingPathComponent(expanded).path }
            guard let path, exists(path) else { continue }
            return .file(path)
        }
        return nil
    }
}
