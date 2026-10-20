import Foundation

/// Every log the app and the CLI keep on this Mac, gathered into one zip the
/// person can attach to a report: the app's logs, the CLI's logs and its
/// command history, and an `about.txt` with the versions.
public enum LogBundle {
    public struct Sources: Equatable, Sendable {
        public var appLogDirectory: URL
        /// The CLI's configuration folder (`devmachine config path`); nil
        /// when the CLI is missing or did not answer.
        public var cliConfigDirectory: URL?
        /// What `devmachine logs path` answered; nil from an older CLI, and
        /// the log is looked for in `<config>/logs` instead.
        public var cliLogFile: URL?

        public init(appLogDirectory: URL, cliConfigDirectory: URL?, cliLogFile: URL? = nil) {
            self.appLogDirectory = appLogDirectory
            self.cliConfigDirectory = cliConfigDirectory
            self.cliLogFile = cliLogFile
        }

        public var cliLog: URL? { cliLogFile ?? cliConfigDirectory.map(LogBundle.cliLog(in:)) }
    }

    public static func cliLog(in configDirectory: URL) -> URL {
        configDirectory.appendingPathComponent("logs/devmachine.log")
    }

    public static func history(in configDirectory: URL) -> URL {
        configDirectory.appendingPathComponent("history.log")
    }

    public static func about(appVersion: String, cliVersion: String, macOS: String, arch: String) -> String {
        """
        App: \(appVersion)
        CLI: \(cliVersion)
        macOS: \(macOS) (\(arch))

        """
    }

    /// The files that go in, in the order they are listed.
    public static func files(in sources: Sources) -> [URL] {
        var files = logs(in: sources.appLogDirectory, named: ["app.log", "terminal.log"])
        if let cliLog = sources.cliLog {
            files += logs(in: cliLog.deletingLastPathComponent(), named: [cliLog.lastPathComponent])
        }
        if let config = sources.cliConfigDirectory {
            let history = history(in: config)
            if FileManager.default.fileExists(atPath: history.path) { files.append(history) }
        }
        return files
    }

    /// Writes `devmachine-logs-<time>.zip` into `destination` and answers its
    /// address. The files are copied into a folder of that name first, so
    /// the zip opens to one folder, and `ditto` packs it.
    public static func write(
        sources: Sources, about: String, to destination: URL, date: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> URL {
        let name = "devmachine-logs-" + stamp(date, timeZone: timeZone)
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = staging.appendingPathComponent(name)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: staging) }
        for file in files(in: sources) {
            try manager.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }
        try Data(about.utf8).write(to: folder.appendingPathComponent("about.txt"))
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let zip = destination.appendingPathComponent(name + ".zip")
        try? manager.removeItem(at: zip)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--keepParent", folder.path, zip.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LogBundleError.zipFailed(String(decoding: message, as: UTF8.self))
        }
        return zip
    }

    private static func logs(in directory: URL, named names: [String]) -> [URL] {
        names.flatMap { name in
            ([name] + (1...AppLogger.keptFiles).map { "\(name).\($0)" })
                .map { directory.appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private static func stamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}

public enum LogBundleError: LocalizedError, Equatable {
    case zipFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .zipFailed(detail):
            let reason = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Could not write the zip" + (reason.isEmpty ? "." : ": \(reason)")
        }
    }
}
