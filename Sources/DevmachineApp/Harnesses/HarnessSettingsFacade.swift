import SwiftUI
import DevmachineCore
import HarnessUsageKit

struct HarnessUsageRegistration: Identifiable {
    let descriptor: HarnessDescriptor
    let provider: any HarnessUsageProvider
    var id: HarnessID { descriptor.id }
}

enum HarnessActivationError: Error, Equatable, Sendable {
    case harnessNotRegistered(HarnessID)
}

/// Where a new session runs, which decides the harnesses it may start: one
/// on this Mac needs the harness's CLI here; a remote one never asks.
enum LaunchPlace: Equatable, Sendable {
    case thisMac
    case remote
}

/// Whether each harness's CLI is on this Mac, looked up once and kept until
/// `refresh`. A CLI that is missing costs a login shell to look for, which a
/// menu or a view body must not pay on every draw.
final class CLIAvailability: @unchecked Sendable {
    static let shared = CLIAvailability()

    private let lock = NSLock()
    private var known: [String: Bool] = [:]

    func isAvailable(_ executable: String, locator: any ExecutableLocating) -> Bool {
        lock.lock()
        if let cached = known[executable] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let found = locator.executable(named: executable) != nil
        lock.lock()
        known[executable] = found
        lock.unlock()
        return found
    }

    /// Looks every name up again, then swaps the answers in at once, so a
    /// reader meanwhile still gets the old answer instead of a lookup.
    func refresh(_ executables: [String], locator: any ExecutableLocating) {
        let fresh = Dictionary(
            executables.map { ($0, locator.executable(named: $0) != nil) }, uniquingKeysWith: { first, _ in first })
        lock.lock()
        known = fresh
        lock.unlock()
    }
}

enum HarnessActivationResult: Equatable, Sendable {
    case success
    case failure(HarnessActivationError)
}

struct HarnessLaunchOption: Identifiable, Sendable {
    let choice: SessionLaunchChoice
    let descriptor: HarnessDescriptor?

    var id: String {
        switch choice {
        case .terminal:
            "terminal"
        case let .harness(harness):
            harness.rawValue
        case let .custom(command):
            "custom:" + command
        }
    }

    var title: String {
        descriptor?.title ?? "Terminal"
    }

    var shortTitle: String {
        descriptor?.shortTitle ?? "Terminal"
    }

    var systemImage: String {
        descriptor?.systemImage ?? "terminal"
    }

    var color: Color? {
        descriptor?.color
    }

    var helpText: String {
        descriptor?.helpText ?? "Start a plain shell"
    }

    static let terminal = HarnessLaunchOption(choice: .terminal, descriptor: nil)
}

struct HarnessSettingsFacade: Sendable {
    let registry: HarnessRegistry
    let locator: any ExecutableLocating
    private let availability: CLIAvailability

    static let remoteOnlyNote = "Not on this Mac — remote workspaces only"

    /// Every facade on the default locator shares one answer per CLI, so
    /// Settings looking again also changes what a new local session starts.
    init(registry: HarnessRegistry = .builtIn, locator: (any ExecutableLocating)? = nil) {
        self.registry = registry
        self.locator = locator ?? Self.defaultLocator()
        self.availability = locator == nil ? .shared : CLIAvailability()
    }

    /// Demo mode never looks at this Mac's tools: its CLIs are `DemoData`'s.
    private static func defaultLocator() -> any ExecutableLocating {
        DemoMode.isActive ? DemoData.executableLocator : SystemExecutableLocator()
    }

    func isOnThisMac(_ id: HarnessID) -> Bool {
        guard let adapter = registry.adapter(for: id) else { return false }
        return availability.isAvailable(adapter.executableName, locator: locator)
    }

    /// Looks every CLI up again (a login shell for each one missing), so
    /// call it off the main thread; reads meanwhile keep the old answers.
    func refreshAvailability() {
        availability.refresh(registry.adapters.map(\.executableName), locator: locator)
    }

    /// The Settings row's note for a harness that is on but can only start
    /// on a remote workspace.
    func remoteOnlyNote(for id: HarnessID, in settings: AppSettings) -> String? {
        settings.enabledHarnesses.contains(id) && !isOnThisMac(id) ? Self.remoteOnlyNote : nil
    }

    /// The local default, or a plain shell when it names a harness whose CLI
    /// is not on this Mac, as a harness turned off falls back.
    func localSessionProgram(for settings: AppSettings) -> SessionLaunchChoice {
        if case let .harness(id) = settings.localSessionProgram, !isOnThisMac(id) { return .terminal }
        return settings.localSessionProgram
    }

    var harnesses: [HarnessDescriptor] {
        registry.adapters.map(\.descriptor)
    }

    func descriptor(for id: HarnessID) -> HarnessDescriptor? {
        registry.adapter(for: id)?.descriptor
    }

    func launchOptions(for settings: AppSettings, on place: LaunchPlace) -> [HarnessLaunchOption] {
        [.terminal] + registry.adapters.compactMap { adapter in
            guard settings.enabledHarnesses.contains(adapter.id),
                  place == .remote || isOnThisMac(adapter.id) else { return nil }
            return HarnessLaunchOption(choice: .harness(adapter.id), descriptor: adapter.descriptor)
        }
    }

    func startupCommand(for choice: SessionLaunchChoice) -> String? {
        switch choice {
        case .terminal:
            return nil
        case let .harness(id):
            return registry.adapter(for: id)?.startupCommand
        case let .custom(command):
            return CustomSessionCommand.normalized(command)
        }
    }

    func usageRegistrations(for settings: AppSettings) -> [HarnessUsageRegistration] {
        registry.adapters.compactMap { adapter in
            guard settings.enabledHarnesses.contains(adapter.id),
                  let provider = adapter.usageProvider(locator: locator) else { return nil }
            return HarnessUsageRegistration(descriptor: adapter.descriptor, provider: provider)
        }
    }

    func enable(_ id: HarnessID, in settings: inout AppSettings) -> HarnessActivationResult {
        guard registry.adapter(for: id) != nil else {
            return .failure(.harnessNotRegistered(id))
        }
        guard !settings.enabledHarnesses.contains(id) else { return .success }

        settings.enabledHarnesses.append(id)
        return .success
    }
}
