import AppKit
import DevmachineCore
import SwiftUI

/// What Help > Logs and ⌘K's log commands do.
enum LogAction: String, Equatable, CaseIterable {
    case openAppLog, openCLILog, openHistory, showInFinder, saveAll

    /// A file not written yet is named "(none yet)" in the menu.
    func title(available: Bool = true) -> String {
        let title: String
        switch self {
        case .openAppLog: title = "Open App Log"
        case .openCLILog: title = "Open CLI Log"
        case .openHistory: title = "Open Command History"
        case .showInFinder: title = "Show Logs in Finder"
        case .saveAll: title = "Save All Logs…"
        }
        return available ? title : title + " (none yet)"
    }
}

/// Where each log is and whether it is there yet. The CLI's folder comes
/// from `devmachine config path` once; the files are looked at again each
/// time the app comes to the front or a menu opens, which is cheap.
@MainActor
final class LogFiles: ObservableObject {
    static let shared = LogFiles()

    let appLogDirectory: URL
    @Published private(set) var configDirectory: URL?
    @Published private(set) var cliLog: URL?
    @Published private(set) var cliLogExists = false
    @Published private(set) var historyExists = false

    /// The CLI's folder and its log, as the installed CLI says.
    struct Resolved: Sendable {
        var configDirectory: URL?
        var cliLog: URL?
    }

    private let resolve: @Sendable () -> Resolved
    private let fileExists: (String) -> Bool
    private var resolving = false

    init(
        appLogDirectory: URL = AppLog.directory,
        resolve: @escaping @Sendable () -> Resolved = LogFiles.liveResolve,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.appLogDirectory = appLogDirectory
        self.resolve = resolve
        self.fileExists = fileExists
    }

    nonisolated static func liveResolve() -> Resolved {
        guard !DemoMode.isActive, let cli = try? DevmachineCLI.resolve(),
              let config = try? cli.configPath().path
        else { return Resolved() }
        let directory = URL(fileURLWithPath: config)
        return Resolved(
            configDirectory: directory,
            cliLog: cli.logsPath().map { URL(fileURLWithPath: $0) } ?? LogBundle.cliLog(in: directory))
    }

    var appLog: URL { appLogDirectory.appendingPathComponent(AppLogger.fileName) }
    var history: URL? { configDirectory.map(LogBundle.history(in:)) }

    private var observers: [NSObjectProtocol] = []

    /// Looks again when the app comes to the front or any menu opens.
    func startWatching() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSMenu.didBeginTrackingNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            })
        }
        Task { await refresh() }
    }

    func refresh() async {
        if configDirectory == nil, !resolving {
            resolving = true
            let resolve = resolve
            let resolved = await Task.detached(priority: .utility) { resolve() }.value
            configDirectory = resolved.configDirectory
            cliLog = resolved.cliLog
            resolving = false
        }
        let cli = cliLog.map { fileExists($0.path) } ?? false
        let history = history.map { fileExists($0.path) } ?? false
        if cli != cliLogExists { cliLogExists = cli }
        if history != historyExists { historyExists = history }
    }

    func isAvailable(_ action: LogAction) -> Bool {
        switch action {
        case .openCLILog: return cliLogExists
        case .openHistory: return historyExists
        case .openAppLog, .showInFinder, .saveAll: return true
        }
    }
}

/// Opens Finder or the default app for a file; a fake in tests.
@MainActor
protocol LogWorkspace {
    func open(_ url: URL)
    func reveal(_ urls: [URL])
}

@MainActor
struct SystemLogWorkspace: LogWorkspace {
    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }
}

/// Runs a `LogAction`. Saving writes the zip off the main thread, then
/// shows it in Finder; what it did is said in a corner toast.
@MainActor
struct LogActionRunner {
    var files: LogFiles = .shared
    var workspace: any LogWorkspace = SystemLogWorkspace()
    var destination: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    var cliVersion: @Sendable () -> String = {
        guard !DemoMode.isActive, let output = try? DevmachineCLI.resolve().version() else { return "unknown" }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var announce: (String) -> Void = { AppModel.shared?.flashToast($0) }

    @discardableResult
    func perform(_ action: LogAction) async -> URL? {
        await files.refresh()
        switch action {
        case .openAppLog:
            writeOpeningLine()
            workspace.open(files.appLog)
            return files.appLog
        case .openCLILog:
            return open(files.cliLog, exists: files.cliLogExists, name: "CLI log")
        case .openHistory:
            return open(files.history, exists: files.historyExists, name: "command history")
        case .showInFinder:
            writeOpeningLine()
            var urls = [files.appLog]
            if files.cliLogExists, let cli = files.cliLog { urls.append(cli) }
            workspace.reveal(urls)
            return files.appLog
        case .saveAll:
            return await saveAll()
        }
    }

    private func open(_ url: URL?, exists: Bool, name: String) -> URL? {
        guard exists, let url else {
            announce("There is no \(name) yet")
            return nil
        }
        workspace.open(url)
        return url
    }

    private func writeOpeningLine() {
        AppLog.shared.info("app", "logs opened from the menu")
        AppLog.shared.flush()
    }

    private func saveAll() async -> URL? {
        AppLog.shared.flush()
        let sources = LogBundle.Sources(
            appLogDirectory: files.appLogDirectory, cliConfigDirectory: files.configDirectory, cliLogFile: files.cliLog)
        let destination = destination
        let cliVersion = cliVersion
        let appVersion = AppLog.appVersion
        let macOS = AppLog.macOSVersion
        let arch = LimaInstaller.thisMac
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                let about = LogBundle.about(appVersion: appVersion, cliVersion: cliVersion(), macOS: macOS, arch: arch)
                return try LogBundle.write(sources: sources, about: about, to: destination)
            }
        }.value
        switch result {
        case let .success(zip):
            AppLog.shared.info("app", "saved logs to \(zip.path)")
            workspace.reveal([zip])
            announce("Saved \(zip.lastPathComponent) to \(destination.lastPathComponent)")
            return zip
        case let .failure(error):
            AppLog.shared.error("app", "saving logs failed: \(error.localizedDescription)")
            announce("Could not save the logs: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Help > Logs.
struct LogsMenu: View {
    @ObservedObject var files: LogFiles

    var body: some View {
        Menu("Logs") {
            item(.openAppLog)
            item(.openCLILog)
            item(.openHistory)
            Divider()
            item(.showInFinder)
            item(.saveAll)
        }
    }

    private func item(_ action: LogAction) -> some View {
        let available = files.isAvailable(action)
        return Button(action.title(available: available)) {
            Task { await LogActionRunner(files: files).perform(action) }
        }
        .disabled(!available)
    }
}
