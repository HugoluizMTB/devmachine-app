import Foundation
import DevmachineCore

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

    private func save() {
        guard let settings, let data = try? JSONEncoder().encode(settings) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
