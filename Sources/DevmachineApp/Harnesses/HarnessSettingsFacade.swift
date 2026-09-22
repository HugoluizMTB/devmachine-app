import SwiftUI
import DevmachineCore
import HarnessUsageKit

struct HarnessUsageRegistration: Identifiable {
    let descriptor: HarnessDescriptor
    let provider: any HarnessUsageProvider
    var id: HarnessID { descriptor.id }
}

enum HarnessActivationError: Error, Equatable, Sendable {
    case cliNotFound(String)
    case harnessNotRegistered(HarnessID)
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

    init(registry: HarnessRegistry = .builtIn, locator: any ExecutableLocating = SystemExecutableLocator()) {
        self.registry = registry
        self.locator = locator
    }

    var harnesses: [HarnessDescriptor] {
        registry.adapters.map(\.descriptor)
    }

    func descriptor(for id: HarnessID) -> HarnessDescriptor? {
        registry.adapter(for: id)?.descriptor
    }

    func launchOptions(for settings: AppSettings) -> [HarnessLaunchOption] {
        [.terminal] + registry.adapters.compactMap { adapter in
            settings.enabledHarnesses.contains(adapter.id)
                ? HarnessLaunchOption(choice: .harness(adapter.id), descriptor: adapter.descriptor)
                : nil
        }
    }

    func startupCommand(for choice: SessionLaunchChoice) -> String? {
        guard case let .harness(id) = choice else { return nil }
        return registry.adapter(for: id)?.startupCommand
    }

    func usageRegistrations(for settings: AppSettings) -> [HarnessUsageRegistration] {
        registry.adapters.compactMap { adapter in
            guard settings.enabledHarnesses.contains(adapter.id),
                  let provider = adapter.usageProvider(locator: locator) else { return nil }
            return HarnessUsageRegistration(descriptor: adapter.descriptor, provider: provider)
        }
    }

    func enable(_ id: HarnessID, in settings: inout AppSettings) -> HarnessActivationResult {
        guard let adapter = registry.adapter(for: id) else {
            return .failure(.harnessNotRegistered(id))
        }
        guard locator.executable(named: adapter.executableName) != nil else {
            return .failure(.cliNotFound(adapter.descriptor.title))
        }
        guard !settings.enabledHarnesses.contains(id) else { return .success }

        settings.enabledHarnesses.append(id)
        return .success
    }
}
