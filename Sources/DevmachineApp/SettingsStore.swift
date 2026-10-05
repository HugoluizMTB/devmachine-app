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

    func launchOptions(using facade: HarnessSettingsFacade, on place: LaunchPlace) -> [HarnessLaunchOption] {
        facade.launchOptions(for: value, on: place)
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

private struct CollapsedSidebarButtonFrameKey: EnvironmentKey {
    static let defaultValue: CGRect? = nil
}

extension EnvironmentValues {
    /// The button that reopens the collapsed sidebar, in `ContentView.windowSpace`;
    /// nil while the sidebar is shown. Home keeps its cards out from under it.
    var collapsedSidebarButtonFrame: CGRect? {
        get { self[CollapsedSidebarButtonFrameKey.self] }
        set { self[CollapsedSidebarButtonFrameKey.self] = newValue }
    }

    var harnessSettingsFacade: HarnessSettingsFacade {
        get { self[HarnessSettingsFacadeKey.self] }
        set { self[HarnessSettingsFacadeKey.self] = newValue }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    /// Single instance for the whole app: `TerminalRegistry` is a singleton too
    /// and has no view environment to read the settings from.
    static let shared = SettingsStore(drivesTextSize: true)

    private static let key = "appSettings"

    @Published var settings: AppSettings? {
        didSet {
            save()
            syncSSHAgentSocketPreference()
            syncTextSize()
        }
    }

    private let defaults: UserDefaults
    private let persists: Bool
    private let drivesTextSize: Bool

    init(defaults: UserDefaults = .standard, drivesTextSize: Bool = false) {
        self.defaults = defaults
        self.drivesTextSize = drivesTextSize
        persists = !DemoMode.isActive
        guard persists else {
            settings = DemoData.settings
            return
        }
        guard let data = defaults.data(forKey: Self.key) else { return }
        settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        syncSSHAgentSocketPreference()
    }

    /// Keeps `RemoteCommands.SSHAgentSocketPreference` current, so any code
    /// that opens an ssh/mosh connection — including `DevmachineCore`, which
    /// cannot see this store — picks up a changed preference for its very
    /// next connection, without threading the setting through by hand.
    private func syncSSHAgentSocketPreference() {
        RemoteCommands.SSHAgentSocketPreference.shared.update(settings?.sshAgentSocket)
    }

    /// Set here, not from a view's `onChange`, so the tree the new setting
    /// rebuilds is drawn at the new size: `onChange` runs after that render,
    /// and a view nothing re-renders kept the old size until hovered.
    private func syncTextSize() {
        guard drivesTextSize else { return }
        DMFont.scale = settings?.uiFontScale ?? Appearance.defaultUIFontScale
    }

    var isConfigured: Bool { settings != nil }

    func draft() -> SettingsDraft {
        SettingsDraft(value: settings ?? .empty)
    }

    func commit(_ draft: SettingsDraft) {
        settings = draft.committedValue
    }

    private func save() {
        guard persists else { return }
        guard let settings, let data = try? JSONEncoder().encode(settings) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
