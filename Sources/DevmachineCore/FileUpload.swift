import Foundation

public struct UploadStoragePolicy: Equatable, Sendable {
    public let directory: String

    public init(directory: String) {
        self.directory = directory
    }

    public static let appManaged = UploadStoragePolicy(directory: ".cache/devmachine-app/uploads")
}

public struct DroppedEntry: Equatable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public let size: Int64

    public init(url: URL, isDirectory: Bool, size: Int64) {
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
    }
}

public struct UploadName: Equatable, Sendable {
    public let stem: String
    public let ext: String

    public init(stem: String, ext: String) {
        self.stem = stem
        self.ext = ext
    }

    public var fileName: String { numbered(1) }

    public func numbered(_ n: Int) -> String {
        n < 2 ? stem + ext : "\(stem)-\(n)\(ext)"
    }

    /// The original name with the time before the extension: the agent and
    /// the person both still recognise the file, and a later upload of the
    /// same file does not replace it.
    public static func make(original: String, date: Date, timeZone: TimeZone = .current) -> UploadName {
        let name = FileUpload.sanitized(original)
        let stamp = FileUpload.stamp(date, timeZone: timeZone)
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex,
              name.index(after: dot) != name.endIndex,
              !name[dot...].contains(where: \.isWhitespace)
        else { return UploadName(stem: "\(name)-\(stamp)", ext: "") }
        return UploadName(stem: "\(name[..<dot])-\(stamp)", ext: String(name[dot...]))
    }
}

public struct UploadItem: Equatable, Sendable {
    public let source: URL
    public let originalName: String
    public let name: UploadName
    public let size: Int64

    public init(source: URL, originalName: String, name: UploadName, size: Int64) {
        self.source = source
        self.originalName = originalName
        self.name = name
        self.size = size
    }
}

public enum UploadRefusal: Error, Equatable, Sendable {
    case folders([String])

    public var title: String {
        "Folders can\u{2019}t be dropped yet \u{2014} drop the files inside"
    }

    public var details: String {
        switch self {
        case let .folders(names): return "Folders in the drop: " + names.joined(separator: ", ")
        }
    }
}

/// Sending a file to the machine that runs a session: the bytes go to that
/// machine's disk under the file's own name, and the agent is given the path,
/// because the agent reads the disk and the clipboard of the machine it runs on.
public enum FileUpload {
    public static let confirmationThreshold: Int64 = 200 * 1024 * 1024
    public static let pastedImageName = "pasted-image.png"

    public static func needsConfirmation(totalBytes: Int64) -> Bool {
        totalBytes > confirmationThreshold
    }

    static func stamp(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f.string(from: date)
    }

    /// Only what cannot live in one path segment, or would end the typed
    /// line, is replaced. Spaces and any other character stay.
    static func sanitized(_ name: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\u{0}").union(.newlines)
        let scalars = name.unicodeScalars.map { unsafe.contains($0) ? "_" : Character($0) }
        let clean = String(scalars)
        return clean.isEmpty || clean == "." || clean == ".." ? "file" : clean
    }

    /// Keeps the drop order. A folder refuses the whole drop, so nothing is
    /// half sent. Two files with the same name are numbered.
    public static func plan(
        _ entries: [DroppedEntry], date: Date, timeZone: TimeZone = .current
    ) throws -> [UploadItem] {
        let folders = entries.filter(\.isDirectory).map(\.url.lastPathComponent)
        guard folders.isEmpty else { throw UploadRefusal.folders(folders) }
        var taken: Set<String> = []
        return entries.map { entry in
            let original = entry.url.lastPathComponent
            let base = UploadName.make(original: original, date: date, timeZone: timeZone)
            var n = 1
            while taken.contains(base.numbered(n)) { n += 1 }
            taken.insert(base.numbered(n))
            let name = n == 1 ? base : UploadName(stem: "\(base.stem)-\(n)", ext: base.ext)
            return UploadItem(source: entry.url, originalName: original, name: name, size: entry.size)
        }
    }

    /// One round trip: make the folder, pick the first free name, write stdin
    /// there, print the absolute path. The name travels as base64 and is
    /// decoded on the host, so no character of it is ever read by the shell.
    public static func writeCommand(name: UploadName, policy: UploadStoragePolicy) -> String {
        let stem = Data(name.stem.utf8).base64EncodedString()
        let ext = Data(name.ext.utf8).base64EncodedString()
        return "d=\"$HOME\"/\(singleQuoted(policy.directory))"
            + " && s=$(printf '%s' '\(stem)' | base64 -d)"
            + " && e=$(printf '%s' '\(ext)' | base64 -d)"
            + " && mkdir -p \"$d\" && f=\"$d/$s$e\" && i=2"
            + " && while [ -e \"$f\" ]; do f=\"$d/$s-$i$e\"; i=$((i+1)); done"
            + " && cat > \"$f\" && printf '%s\\n' \"$f\""
    }

    /// Only the final line break is the host's; anything else belongs to the
    /// name, which may end in a space.
    public static func writtenPath(from output: String, name: UploadName) -> String? {
        var path = output
        if path.hasSuffix("\n") { path.removeLast() }
        guard path.hasPrefix("/"), !path.contains("\n"),
              let last = path.split(separator: "/").last,
              last.hasPrefix(name.stem), last.hasSuffix(name.ext)
        else { return nil }
        return path
    }

    public static func typedText(for paths: [String]) -> String {
        paths.map(shellQuoted).joined(separator: " ") + " "
    }

    public static func shellQuoted(_ path: String) -> String {
        let plain = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+@%:,=")
        if !path.isEmpty, path.unicodeScalars.allSatisfy(plain.contains) { return path }
        return singleQuoted(path)
    }

    public static func byteText(_ bytes: Int64) -> String {
        guard bytes >= 1024 else { return "\(bytes) B" }
        var value = Double(bytes) / 1024
        for unit in ["KB", "MB", "GB"] {
            if value < 1024 || unit == "GB" {
                return String(format: "%.1f %@", locale: Locale(identifier: "en_US_POSIX"), value, unit)
            }
            value /= 1024
        }
        return "\(bytes) B"
    }

    public static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
