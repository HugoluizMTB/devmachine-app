import Foundation
import SwiftUI
import DevmachineCore

struct SettingsDraft: Equatable {
    var value: AppSettings

    init(value: AppSettings = .empty) {
        self.value = value
    }

    var committedValue: AppSettings {
        var result = value
        result.opsRepoPath = result.opsRepoPath.trimmingCharacters(in: .whitespaces)
        result.hostAlias = result.hostAlias.trimmingCharacters(in: .whitespaces)
        result.publicIP = result.publicIP.trimmingCharacters(in: .whitespaces)
        result.baseDomain = result.baseDomain.trimmingCharacters(in: .whitespaces)
        return result
    }

    func launchOptions(using facade: HarnessSettingsFacade) -> [HarnessLaunchOption] {
        facade.launchOptions(for: value)
    }

    mutating func setHarness(
        _ id: HarnessID,
        enabled: Bool,
        using facade: HarnessSettingsFacade
    ) -> HarnessActivationResult {
        if enabled {
            return facade.enable(id, in: &value)
        }

        // AppSettings owns normalization so the draft and persisted settings
        // cannot disagree about what disabling a harness means.
        value.enabledHarnesses.removeAll { $0 == id }
        return .success
    }
}

private struct HarnessSettingsFacadeKey: EnvironmentKey {
    static let defaultValue = HarnessSettingsFacade()
}

extension EnvironmentValues {
    var harnessSettingsFacade: HarnessSettingsFacade {
        get { self[HarnessSettingsFacadeKey.self] }
        set { self[HarnessSettingsFacadeKey.self] = newValue }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    /// Single instance for the whole app: `TerminalRegistry` is a singleton too
    /// and has no view environment to read the settings from.
    static let shared = SettingsStore()

    private static let key = "appSettings"

    @Published var settings: AppSettings? {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else { return }
        settings = try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    var isConfigured: Bool { settings != nil }

    func draft() -> SettingsDraft {
        SettingsDraft(value: settings ?? .empty)
    }

    func commit(_ draft: SettingsDraft) {
        settings = draft.committedValue
    }

    private func save() {
        guard let settings, let data = try? JSONEncoder().encode(settings) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
