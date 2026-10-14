import Foundation
import DevmachineCore

/// The website needs real-looking screenshots without ever touching a real
/// machine or the owner's own data. `DEVMACHINE_DEMO=1` switches every store
/// to invented sample data instead of the CLI, ssh, gh, or the Claude/Codex
/// usage files on disk.
///
/// Every place that reads live state checks `DemoMode.isActive` first and,
/// if set, seeds its `@Published` fields from `DemoData` directly — it never
/// calls into `DevmachineCLI`, `GHClient`, `CaddyService`, `HostRunner`, or a
/// `CommandRunner`. `DemoMode.runner` exists only as a defense-in-depth net:
/// if some path is ever wired to it by mistake, it throws instead of
/// shelling out.
enum DemoMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["DEVMACHINE_DEMO"] == "1"
    }

    /// `DEVMACHINE_DEMO_LOADING=1` on top of demo mode: every store stays on
    /// its first load for ever, so the skeletons can be looked at.
    static var holdsLoading: Bool {
        isActive && ProcessInfo.processInfo.environment["DEVMACHINE_DEMO_LOADING"] == "1"
    }

    /// Handed to any initializer that still requires a `CommandRunner` value
    /// while in demo mode (there is nothing real for it to run). Throws on
    /// every call, so a code path that reaches it fails loudly instead of
    /// quietly touching a real machine.
    static let runner: any CommandRunner = DemoCommandRunner()

    /// Home and both sidebars read their board files from this one folder,
    /// never the real configuration.
    static let boardsFolder: String = {
        let folder = ProcessInfo.processInfo.environment["DEVMACHINE_DEMO_BOARDS"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("devmachine-demo-config-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// `ContextStore`'s source, picked once here so nothing else has to ask
    /// `DemoMode.isActive` before building one.
    static func defaultContextSource() -> any ContextSource {
        isActive ? (DemoContextSource() as any ContextSource) : (CLIContextSource() as any ContextSource)
    }
}

/// A `ContextSource` that hands back the same fixed `DemoData.contextState`
/// for every target — used only in demo mode, in place of `CLIContextSource`,
/// which shells out to the CLI or reads real session transcripts.
struct DemoContextSource: ContextSource {
    func context(for target: CommandTarget, settings: AppSettings) throws -> ContextState? {
        DemoContextOverride.shared.value ?? DemoData.contextState(for: target)
    }
}

/// The context every session answers with while the site walk moves a plan
/// along. Read off the main thread by `ContextStore`'s poll, hence the lock.
final class DemoContextOverride: @unchecked Sendable {
    static let shared = DemoContextOverride()

    private let lock = NSLock()
    private var stored: ContextState?

    var value: ContextState? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

enum DemoModeError: Error, LocalizedError {
    case commandRunnerInvoked(executable: String)

    var errorDescription: String? {
        switch self {
        case let .commandRunnerInvoked(executable):
            return "demo mode invoked a real command runner: \(executable)"
        }
    }
}

/// A `CommandRunner` that never runs anything. Demo mode seeds its stores
/// directly and should never construct a runner that actually executes, but
/// this stands in wherever an initializer still asks for one, and a unit
/// test asserts it is never called.
struct DemoCommandRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        throw DemoModeError.commandRunnerInvoked(executable: executable)
    }

    func run(
        executable: String, args: [String], environment: [String: String]?, input: Data,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> String {
        throw DemoModeError.commandRunnerInvoked(executable: executable)
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        throw DemoModeError.commandRunnerInvoked(executable: executable)
    }
}
