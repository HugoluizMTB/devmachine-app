import AppKit
import DevmachineCore
import os

/// The app's log, always on: `~/Library/Logs/Devmachine/app.log`. Under
/// tests it goes to a temporary folder instead, so no test writes into the
/// person's logs.
enum AppLog {
    static let directory: URL = {
        if NSClassFromString("XCTestCase") != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("devmachine-app-log-tests-\(ProcessInfo.processInfo.processIdentifier)")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Devmachine")
    }()

    static let shared = AppLogger(directory: directory)

    /// Settings → Debug logging also writes every poll and every debug line.
    static func applyDebugLogging(_ isOn: Bool) {
        shared.level = isOn ? .debug : .info
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }

    static var macOSVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    /// The first lines of a launch: which app, which macOS, which CLI.
    static func recordLaunch(
        cli: @escaping @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() }
    ) {
        shared.info("app", "Devmachine \(appVersion) started on macOS \(macOSVersion) (\(LimaInstaller.thisMac))")
        guard !DemoMode.isActive else {
            shared.info("app", "demo mode: no CLI is run")
            return
        }
        Task.detached(priority: .utility) {
            do {
                let instance = try cli()
                let version = (try? instance.version())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
                shared.info("app", "CLI \(instance.executable): \(version)")
            } catch {
                shared.warning("app", "CLI not found: \(error.localizedDescription)")
            }
        }
    }
}

/// What used to be an `os.Logger`: the line still goes to the unified log,
/// and now also to the app's log file.
struct AppLogChannel: Sendable {
    let category: String
    private let system: Logger

    init(category: String) {
        self.category = category
        system = Logger(subsystem: "app.devmachine.mac", category: category)
    }

    func debug(_ message: String) {
        system.debug("\(LogRedactor.redact(message), privacy: .public)")
        AppLog.shared.debug(category, message)
    }

    func info(_ message: String) {
        system.info("\(LogRedactor.redact(message), privacy: .public)")
        AppLog.shared.info(category, message)
    }

    func error(_ message: String) {
        system.error("\(LogRedactor.redact(message), privacy: .public)")
        AppLog.shared.error(category, message)
    }
}
